{-# LANGUAGE CPP #-}

-- -----------------------------------------------------------------------------
-- | GHC LLVM Mangler
--
-- This script processes the assembly produced by LLVM, rearranging the code
-- so that an info table appears before its corresponding function.
--

module LlvmMangler ( llvmFixupAsm ) where

import DynFlags ( DynFlags )
import ErrUtils ( showPass )

import Control.Exception
import Control.Monad ( when )
import qualified Data.ByteString.Char8 as B
import System.IO

#if x86_64_TARGET_ARCH
#define REWRITE_AVX
#endif

-- Magic Strings
secStmt, newLine, textStmt, dataStmt, syntaxUnified :: B.ByteString
secStmt       = B.pack "\t.section\t"
newLine       = B.pack "\n"
textStmt      = B.pack "\t.text"
dataStmt      = B.pack "\t.data"
syntaxUnified = B.pack "\t.syntax unified"

-- Search Predicates
isType :: B.ByteString -> Bool
isType = B.isPrefixOf (B.pack "\t.type")

-- section of a file in the form of (header line, contents)
type Section = (B.ByteString, B.ByteString)

-- | Read in assembly file and process
llvmFixupAsm :: DynFlags -> FilePath -> FilePath -> IO ()
llvmFixupAsm dflags f1 f2 = {-# SCC "llvm_mangler" #-} do
    showPass dflags "LLVM Mangler"
    r <- openBinaryFile f1 ReadMode
    w <- openBinaryFile f2 WriteMode
    ss <- readSections r w
    hClose r
    let fixed = map rewriteAVX ss
    mapM_ (writeSection w) fixed
    hClose w
    return ()

-- | This rewrites @.type@ annotations of function symbols to @%object@.
-- This is done as the linker can relocate @%functions@ through the
-- Procedure Linking Table (PLT). This is bad since we expect that the
-- info table will appear directly before the symbol's location. In the
-- case that the PLT is used, this will be not an info table but instead
-- some random PLT garbage.
rewriteSymType :: B.ByteString -> B.ByteString
rewriteSymType s =
    B.unlines $ map (rewrite '@' . rewrite '%') $ B.lines s
  where
    rewrite :: Char -> B.ByteString -> B.ByteString
    rewrite prefix x
        | isType x = replace funcType objType x
        | otherwise = x
      where
        funcType = prefix `B.cons` B.pack "function"
        objType  = prefix `B.cons` B.pack "object"

-- | Splits the file contents into its sections
readSections :: Handle -> Handle -> IO [Section]
readSections r w = go B.empty [] []
  where
    go hdr ss ls = do
      e_l <- (try (B.hGetLine r))::IO (Either IOError B.ByteString)

      -- Note that ".type" directives at the end of a section refer to
      -- the first directive of the *next* section, therefore we take
      -- it over to that section.
      let (tys, ls') = span isType ls
          cts = rewriteSymType $ B.intercalate newLine $ reverse ls'

      -- Decide whether to directly output the section or append it
      -- to the list for resorting.
      let finishSection = writeSection w (hdr, cts) >> return ss

      case e_l of
        Right l | l == syntaxUnified
                  -> finishSection >>= \ss' -> writeSection w (l, B.empty)
                                   >> go B.empty ss' tys
                | any (`B.isPrefixOf` l) [secStmt, textStmt, dataStmt]
                  -> finishSection >>= \ss' -> go l ss' tys
                | otherwise
                  -> go hdr ss (l:ls)
        Left _    -> finishSection >>= \ss' -> return (reverse ss')

-- | Writes sections back
writeSection :: Handle -> Section -> IO ()
writeSection w (hdr, cts) = do
  when (not $ B.null hdr) $
    B.hPutStrLn w hdr
  B.hPutStrLn w cts

#if REWRITE_AVX
rewriteAVX :: Section -> Section
rewriteAVX = rewriteVmovaps . rewriteVmovdqa

rewriteVmovdqa :: Section -> Section
rewriteVmovdqa = rewriteInstructions vmovdqa vmovdqu
  where
    vmovdqa, vmovdqu :: B.ByteString
    vmovdqa = B.pack "vmovdqa"
    vmovdqu = B.pack "vmovdqu"

rewriteVmovap :: Section -> Section
rewriteVmovap = rewriteInstructions vmovap vmovup
  where
    vmovap, vmovup :: B.ByteString
    vmovap = B.pack "vmovap"
    vmovup = B.pack "vmovup"

rewriteInstructions :: B.ByteString -> B.ByteString -> Section -> Section
rewriteInstructions matchBS replaceBS (hdr, cts) =
    (hdr, replace matchBS replaceBS cts)
#else /* !REWRITE_AVX */
rewriteAVX :: Section -> Section
rewriteAVX = id
#endif /* !REWRITE_SSE */

replace :: B.ByteString -> B.ByteString -> B.ByteString -> B.ByteString
replace matchBS replaceBS = loop
  where
    loop :: B.ByteString -> B.ByteString
    loop cts =
        case B.breakSubstring matchBS cts of
          (hd,tl) | B.null tl -> hd
                  | otherwise -> hd `B.append` replaceBS `B.append`
                                 loop (B.drop (B.length matchBS) tl)