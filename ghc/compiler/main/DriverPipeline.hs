-----------------------------------------------------------------------------
--
-- GHC Driver
--
-- (c) The University of Glasgow 2002
--
-----------------------------------------------------------------------------

#include "../includes/config.h"

module DriverPipeline (

	-- Interfaces for the batch-mode driver
   genPipeline, runPipeline, pipeLoop, staticLink,

	-- Interfaces for the compilation manager (interpreted/batch-mode)
   preprocess, 
   compile, CompResult(..), 
   link, 

        -- DLL building
   doMkDLL
  ) where

#include "HsVersions.h"

import Packages
import GetImports
import DriverState
import DriverUtil
import DriverMkDepend
import DriverPhases
import DriverFlags
import SysTools		( newTempName, addFilesToClean, getSysMan, copy )
import qualified SysTools	
import HscMain
import Finder
import HscTypes
import Outputable
import Module
import ErrUtils
import CmdLineOpts
import Config
import Panic
import Util
import BasicTypes	( SuccessFlag(..) )
import Maybes		( expectJust )

import ParserCoreUtils ( getCoreModuleName )

import EXCEPTION
import DATA_IOREF	( readIORef, writeIORef )

#ifdef GHCI
import Time 		( getClockTime )
#endif
import Directory
import System
import IO
import Monad
import Maybe


-- ---------------------------------------------------------------------------
-- Pre-process

-- Just preprocess a file, put the result in a temp. file (used by the
-- compilation manager during the summary phase).

preprocess :: FilePath -> IO FilePath
preprocess filename =
  ASSERT(haskellish_src_file filename) 
  do restoreDynFlags	-- Restore to state of last save
     let fInfo = (filename, getFileSuffix filename)
     pipeline <- genPipeline (StopBefore Hsc) ("preprocess") False 
			     defaultHscLang fInfo
     (fn,_)   <- runPipeline pipeline fInfo
     	                     False{-no linking-} False{-no -o flag-}
     return fn

-- ---------------------------------------------------------------------------
-- Compile

-- Compile a single module, under the control of the compilation manager.
--
-- This is the interface between the compilation manager and the
-- compiler proper (hsc), where we deal with tedious details like
-- reading the OPTIONS pragma from the source file, and passing the
-- output of hsc through the C compiler.

-- The driver sits between 'compile' and 'hscMain', translating calls
-- to the former into calls to the latter, and results from the latter
-- into results from the former.  It does things like preprocessing
-- the .hs file if necessary, and compiling up the .stub_c files to
-- generate Linkables.

-- NB.  No old interface can also mean that the source has changed.

compile :: GhciMode                -- distinguish batch from interactive
	-> Module
	-> ModLocation
	-> Bool			   -- True <=> source unchanged
	-> Bool			   -- True <=> have object
        -> Maybe ModIface          -- old interface, if available
        -> HomePackageTable        -- For home-module stuff
        -> PersistentCompilerState -- persistent compiler state
        -> IO CompResult

data CompResult
   = CompOK   PersistentCompilerState	-- Updated PCS
              ModDetails 		-- New details
              ModIface			-- New iface
              (Maybe Linkable)	-- New code; Nothing => compilation was not reqd
		                --			(old code is still valid)

   | CompErrs PersistentCompilerState	-- Updated PCS


compile ghci_mode this_mod location
	source_unchanged have_object 
	old_iface hpt pcs = do 

   dyn_flags <- restoreDynFlags		-- Restore to the state of the last save

   showPass dyn_flags 
	(showSDoc (text "Compiling" <+> ppr this_mod))

   let verb	  = verbosity dyn_flags
   let input_fn   = expectJust "compile:hs" (ml_hs_file location) 
   let input_fnpp = expectJust "compile:hspp" (ml_hspp_file location)
   let mod_name   = moduleName this_mod

   when (verb >= 2) (hPutStrLn stderr ("compile: input file " ++ input_fnpp))

   opts <- getOptionsFromSource input_fnpp
   processArgs dynamic_flags opts []
   dyn_flags <- getDynFlags

   let hsc_lang      = hscLang dyn_flags
       (basename, _) = splitFilename input_fn
       
   keep_hc <- readIORef v_Keep_hc_files
#ifdef ILX
   keep_il <- readIORef v_Keep_il_files
#endif
   keep_s  <- readIORef v_Keep_s_files

   output_fn <- 
	case hsc_lang of
	   HscAsm  | keep_s    -> return (basename ++ '.':phaseInputExt As)
		   | otherwise -> newTempName (phaseInputExt As)
	   HscC    | keep_hc   -> return (basename ++ '.':phaseInputExt HCc)
		   | otherwise -> newTempName (phaseInputExt HCc)
           HscJava             -> newTempName "java" -- ToDo
#ifdef ILX
	   HscILX  | keep_il   -> return (basename ++ '.':phaseInputExt Ilasm)
                   | otherwise -> newTempName (phaseInputExt Ilx2Il) 	
#endif
	   HscInterpreted      -> return (error "no output file")
           HscNothing	       -> return (error "no output file")

   let dyn_flags' = dyn_flags { hscOutName = output_fn,
				hscStubCOutName = basename ++ "_stub.c",
				hscStubHOutName = basename ++ "_stub.h",
				extCoreName = basename ++ ".hcr" }

   -- -no-recomp should also work with --make
   do_recomp <- readIORef v_Recomp
   let source_unchanged' = source_unchanged && do_recomp
       hsc_env = HscEnv { hsc_mode = ghci_mode,
			  hsc_dflags = dyn_flags',
			  hsc_HPT    = hpt }

   -- run the compiler
   hsc_result <- hscMain hsc_env pcs this_mod location
			 source_unchanged' have_object old_iface

   case hsc_result of
      HscFail pcs -> return (CompErrs pcs)

      HscNoRecomp pcs details iface -> return (CompOK pcs details iface Nothing)

      HscRecomp pcs details iface
	stub_h_exists stub_c_exists maybe_interpreted_code -> do
	   let 
	   maybe_stub_o <- compileStub dyn_flags' stub_c_exists
	   let stub_unlinked = case maybe_stub_o of
				  Nothing -> []
				  Just stub_o -> [ DotO stub_o ]

	   (hs_unlinked, unlinked_time) <-
	     case hsc_lang of

		-- in interpreted mode, just return the compiled code
		-- as our "unlinked" object.
		HscInterpreted -> 
		    case maybe_interpreted_code of
#ifdef GHCI
		       Just comp_bc -> do tm <- getClockTime 
                                          return ([BCOs comp_bc], tm)
#endif
		       Nothing -> panic "compile: no interpreted code"

		-- we're in batch mode: finish the compilation pipeline.
		_other -> do pipe <- genPipeline (StopBefore Ln) "" True 
					hsc_lang (output_fn, getFileSuffix output_fn)
                             -- runPipeline takes input_fn so it can split off 
                             -- the base name and use it as the base of 
                             -- the output object file.
                             let (basename, suffix) = splitFilename input_fn
			     (o_file,_) <- 
			         pipeLoop pipe (output_fn, getFileSuffix output_fn)
			     		       False False 
                                               basename suffix
                             o_time <- getModificationTime o_file
			     return ([DotO o_file], o_time)

	   let linkable = LM unlinked_time mod_name
			     (hs_unlinked ++ stub_unlinked)

	   return (CompOK pcs details iface (Just linkable))

-----------------------------------------------------------------------------
-- stub .h and .c files (for foreign export support)

compileStub dflags stub_c_exists
  | not stub_c_exists = return Nothing
  | stub_c_exists = do
	-- compile the _stub.c file w/ gcc
	let stub_c = hscStubCOutName dflags
	pipeline   <- genPipeline (StopBefore Ln) "" True defaultHscLang (stub_c,"c")
	(stub_o,_) <- runPipeline pipeline (stub_c,"c") False{-no linking-} 
			          False{-no -o option-}
	return (Just stub_o)


-- ---------------------------------------------------------------------------
-- Link

link :: GhciMode		-- interactive or batch
     -> DynFlags		-- dynamic flags
     -> Bool			-- attempt linking in batch mode?
     -> HomePackageTable	-- what to link
     -> IO SuccessFlag

-- For the moment, in the batch linker, we don't bother to tell doLink
-- which packages to link -- it just tries all that are available.
-- batch_attempt_linking should only be *looked at* in batch mode.  It
-- should only be True if the upsweep was successful and someone
-- exports main, i.e., we have good reason to believe that linking
-- will succeed.

#ifdef GHCI
link Interactive dflags batch_attempt_linking hpt
    = do -- Not Linking...(demand linker will do the job)
	 return Succeeded
#endif

link Batch dflags batch_attempt_linking hpt
   | batch_attempt_linking
   = do 
	let 
	    home_mod_infos = moduleEnvElts hpt

	    -- the packages we depend on
	    pkg_deps  = concatMap (dep_pkgs . mi_deps . hm_iface) home_mod_infos

	    -- the linkables to link
	    linkables = map hm_linkable home_mod_infos

        when (verb >= 3) $ do
	     hPutStrLn stderr "link: linkables are ..."
             hPutStrLn stderr (showSDoc (vcat (map ppr linkables)))

	-- check for the -no-link flag
	omit_linking <- readIORef v_NoLink
	if omit_linking 
	  then do when (verb >= 3) $
		    hPutStrLn stderr "link(batch): linking omitted (-no-link flag given)."
	          return Succeeded
	  else do

	when (verb >= 1) $
             hPutStrLn stderr "Linking ..."

	let getOfiles (LM _ _ us) = map nameOfObject (filter isObject us)
	    obj_files = concatMap getOfiles linkables

	-- Don't showPass in Batch mode; doLink will do that for us.
        staticLink obj_files pkg_deps

        when (verb >= 3) (hPutStrLn stderr "link: done")

	-- staticLink only returns if it succeeds
        return Succeeded

   | otherwise
   = do when (verb >= 3) $ do
	    hPutStrLn stderr "link(batch): upsweep (partially) failed OR"
            hPutStrLn stderr "   Main.main not exported; not linking."
        return Succeeded
   where
      verb = verbosity dflags
      



-- --------------------------------------------------------------------------
-- genPipeline: Pipeline construction

-- Herein is all the magic about which phases to run in which order, whether
-- the intermediate files should be in TMPDIR or in the current directory,
-- what the suffix of the intermediate files should be, etc.

-- The following compilation pipeline algorithm is fairly hacky.  A
-- better way to do this would be to express the whole compilation as a
-- data flow DAG, where the nodes are the intermediate files and the
-- edges are the compilation phases.  This framework would also work
-- nicely if a haskell dependency generator was included in the
-- driver.

-- It would also deal much more cleanly with compilation phases that
-- generate multiple intermediates, (eg. hsc generates .hc, .hi, and
-- possibly stub files), where some of the output files need to be
-- processed further (eg. the stub files need to be compiled by the C
-- compiler).

-- A cool thing to do would then be to execute the data flow graph
-- concurrently, automatically taking advantage of extra processors on
-- the host machine.  For example, when compiling two Haskell files
-- where one depends on the other, the data flow graph would determine
-- that the C compiler from the first compilation can be overlapped
-- with the hsc compilation for the second file.

data IntermediateFileType
  = Temporary
  | Persistent
  deriving (Eq, Show)

genPipeline
   :: GhcMode		 -- when to stop
   -> String		 -- "stop after" flag (for error messages)
   -> Bool		 -- True => output is persistent
   -> HscLang		 -- preferred output language for hsc
   -> (FilePath, String) -- original filename & its suffix 
   -> IO [ 		-- list of phases to run for this file
	     (Phase,
	      IntermediateFileType,  -- keep the output from this phase?
	      String)   	     -- output file suffix
         ]	

genPipeline todo stop_flag persistent_output lang (filename,suffix)
 = do
   split      <- readIORef v_Split_object_files
   mangle     <- readIORef v_Do_asm_mangling
   keep_hc    <- readIORef v_Keep_hc_files
#ifdef ILX
   keep_il    <- readIORef v_Keep_il_files
   keep_ilx   <- readIORef v_Keep_ilx_files
#endif
   keep_raw_s <- readIORef v_Keep_raw_s_files
   keep_s     <- readIORef v_Keep_s_files
   osuf       <- readIORef v_Object_suf
   hcsuf      <- readIORef v_HC_suf

   let
   ----------- -----  ----   ---   --   --  -  -  -
    start = startPhase suffix

      -- special case for mkdependHS: .hspp files go through MkDependHS
    start_phase | todo == DoMkDependHS && start == Hsc  = MkDependHS
	        | otherwise = start

    haskellish = haskellish_suffix suffix
    cish = cish_suffix suffix

       -- for a .hc file we need to force lang to HscC
    real_lang | start_phase == HCc || start_phase == Mangle = HscC
	      | otherwise                                   = lang

   let
   ----------- -----  ----   ---   --   --  -  -  -
    pipeline = preprocess ++ compile

    preprocess
	| haskellish = [ Unlit, Cpp, HsPp ]
	| otherwise  = [ ]

    compile
      | todo == DoMkDependHS = [ MkDependHS ]

      | cish = [ Cc, As ]

      | haskellish = 
       case real_lang of
	HscC    | split && mangle -> [ Hsc, HCc, Mangle, SplitMangle, SplitAs ]
	        | mangle          -> [ Hsc, HCc, Mangle, As ]
	        | split	       	  -> not_valid
	        | otherwise       -> [ Hsc, HCc, As ]

	HscAsm  | split           -> [ Hsc, SplitMangle, SplitAs ]
	        | otherwise       -> [ Hsc, As ]

	HscJava	| split	          -> not_valid
		| otherwise       -> error "not implemented: compiling via Java"
#ifdef ILX
	HscILX  | split           -> not_valid
		| otherwise       -> [ Hsc, Ilx2Il, Ilasm ]
#endif
	HscNothing		  -> [ Hsc, HCc ] -- HCc is a dummy stop phase

      | otherwise = [ ]  -- just pass this file through to the linker

	-- ToDo: this is somewhat cryptic
    not_valid = throwDyn (UsageError ("invalid option combination"))

    stop_phase = case todo of 
			StopBefore As | split -> SplitAs
#ifdef ILX
                                      | real_lang == HscILX -> Ilasm
#endif
			StopBefore phase      -> phase
			DoMkDependHS	      -> Ln
			DoLink                -> Ln
			DoMkDLL               -> Ln
   ----------- -----  ----   ---   --   --  -  -  -

	-- this shouldn't happen.
   when (start_phase /= Ln && start_phase `notElem` pipeline)
	(throwDyn (CmdLineError ("can't find starting phase for "
			         ++ filename)))
	-- if we can't find the phase we're supposed to stop before,
	-- something has gone wrong.  This test carefully avoids the
	-- case where we aren't supposed to do any compilation, because the file
	-- is already in linkable form (for example).
--   hPutStrLn stderr (show ((start_phase `elem` pipeline,stop_phase /= Ln,stop_phase `notElem` pipeline), start_phase, stop_phase, pipeline,todo))
--   hFlush stderr
   when (start_phase `elem` pipeline && 
   	 (stop_phase /= Ln && stop_phase `notElem` pipeline))
        (do
	  throwDyn (UsageError 
		    ("flag `" ++ stop_flag
		     ++ "' is incompatible with source file `"
		     ++ filename ++ "'" ++ show pipeline ++ show stop_phase)))
   let
	-- .o and .hc suffixes can be overriden by command-line options:
      myPhaseInputExt HCc | Just s <- hcsuf = s
      myPhaseInputExt Ln    = osuf
      myPhaseInputExt other = phaseInputExt other

      annotatePipeline
	 :: [Phase]		-- raw pipeline
	 -> Phase		-- phase to stop before
     	 -> [(Phase, IntermediateFileType, String{-file extension-})]
      annotatePipeline []     _    = []
      annotatePipeline (Ln:_) _    = []
      annotatePipeline (phase:next_phase:ps) stop = 
     	  (phase, keep_this_output, myPhaseInputExt next_phase)
	     : annotatePipeline (next_phase:ps) stop
     	  where
     		keep_this_output
     		     | next_phase == stop 
                     = if persistent_output then Persistent else Temporary
     		     | otherwise
     		     = case next_phase of
     			     Ln -> Persistent
     			     Mangle | keep_raw_s -> Persistent
     			     As     | keep_s     -> Persistent
     			     HCc    | keep_hc    -> Persistent
#ifdef ILX
			     Ilx2Il | keep_ilx   -> Persistent
			     Ilasm  | keep_il    -> Persistent
#endif
     			     _other              -> Temporary

	-- add information about output files to the pipeline
	-- the suffix on an output file is determined by the next phase
	-- in the pipeline, so we add linking to the end of the pipeline
	-- to force the output from the final phase to be a .o file.

      annotated_pipeline = annotatePipeline (pipeline ++ [Ln]) stop_phase

      phase_ne p (p1,_,_) = (p1 /= p)
   ----------- -----  ----   ---   --   --  -  -  -

   return (
     takeWhile (phase_ne stop_phase ) $
     dropWhile (phase_ne start_phase) $
     annotated_pipeline
    )


runPipeline
  :: [ (Phase, IntermediateFileType, String) ] -- phases to run
  -> (String,String)		-- input file
  -> Bool			-- doing linking afterward?
  -> Bool			-- take into account -o when generating output?
  -> IO (String, String)	-- return final filename

runPipeline pipeline (input_fn,suffix) do_linking use_ofile
  = pipeLoop pipeline (input_fn,suffix) do_linking use_ofile basename suffix
  where (basename, _) = splitFilename input_fn

pipeLoop [] input_fn _ _ _ _ = return input_fn
pipeLoop (all_phases@((phase, keep, o_suffix):phases))
	(input_fn,real_suff) do_linking use_ofile orig_basename orig_suffix
  = do

     output_fn <- outputFileName (null phases) keep o_suffix

     mbCarryOn <- run_phase phase orig_basename orig_suffix
     			    input_fn output_fn 
	-- sometimes we bail out early, eg. when the compiler's recompilation
	-- checker has determined that recompilation isn't necessary.
     case mbCarryOn of
       Nothing -> do
	      let (_,keep,final_suffix) = last all_phases
	      ofile <- outputFileName True keep final_suffix
	      return (ofile, final_suffix)
          -- carry on ...
       Just fn -> do
		{-
		  Check to see whether we've reached the end of the
		  pipeline, but did so with an ineffective last stage.
		  (i.e., it returned the input_fn as the output filename).
		  
		  If we did and the output is persistent, copy the contents
		  of input_fn into the file where the pipeline's output is
		  expected to end up.
		-}
	      atEnd <- finalStage (null phases)
	      when (atEnd && fn == input_fn)
	      	   (copy "Saving away compilation pipeline's output"
		   	 input_fn
			 output_fn)
              {-
	       Notice that in order to keep the invariant that we can
	       determine a compilation pipeline's 'start phase' just
	       by looking at the input filename, the input filename
	       to the next stage/phase is associated here with the suffix
	       of the output file, *even* if it does not have that
	       suffix in reality.
	       
	       Why is this important? Because we may run a compilation
	       pipeline in stages (cf. Main.main.compileFile's two stages),
	       so when generating the next stage we need to be precise
	       about what kind of file (=> suffix) is given as input.

	       [Not having to generate a pipeline in stages seems like
	        the right way to go, but I've punted on this for now --sof]
	       
	      -}
              pipeLoop phases (fn, o_suffix) do_linking use_ofile
       			orig_basename orig_suffix
  where
     finalStage lastPhase = do
       o_file <- readIORef v_Output_file
       return (lastPhase && not do_linking && use_ofile && isJust o_file)

     outputFileName last_phase keep suffix
  	= do o_file <- readIORef v_Output_file
	     atEnd  <- finalStage last_phase
   	     if atEnd
   	       then case o_file of 
   		       Just s  -> return s
   		       Nothing -> error "outputFileName"
   	       else if keep == Persistent
   			   then odir_ify (orig_basename ++ '.':suffix)
   			   else newTempName suffix

run_phase :: Phase
	  -> String                -- basename of original input source
	  -> String		   -- its extension
	  -> FilePath		   -- name of file which contains the input to this phase.
	  -> FilePath              -- where to stick the result.
	  -> IO (Maybe FilePath)
	  	  -- Nothing => stop the compilation pipeline
		  -- Just fn => the result of this phase can be found in 'fn'
		  --            (this can either be 'input_fn' or 'output_fn').
-------------------------------------------------------------------------------
-- Unlit phase 

run_phase Unlit _basename _suff input_fn output_fn
  = do unlit_flags <- getOpts opt_L
       -- The -h option passes the file name for unlit to put in a #line directive
       SysTools.runUnlit (map SysTools.Option unlit_flags ++
       			  [ SysTools.Option     "-h"
 			  , SysTools.Option     input_fn
			  , SysTools.FileOption "" input_fn
			  , SysTools.FileOption "" output_fn
			  ])
       return (Just output_fn)

-------------------------------------------------------------------------------
-- Cpp phase 

run_phase Cpp basename suff input_fn output_fn
  = do src_opts <- getOptionsFromSource input_fn
       unhandled_flags <- processArgs dynamic_flags src_opts []
       checkProcessArgsResult unhandled_flags basename suff

       do_cpp <- dynFlag cppFlag
       if not do_cpp then
           -- no need to preprocess CPP, just pass input file along
	   -- to the next phase of the pipeline.
          return (Just input_fn)
	else do
	    hscpp_opts	    <- getOpts opt_P
       	    hs_src_cpp_opts <- readIORef v_Hs_source_cpp_opts

	    cmdline_include_paths <- readIORef v_Include_paths

	    pkg_include_dirs <- getPackageIncludePath []
	    let include_paths = foldr (\ x xs -> "-I" : x : xs) []
				  (cmdline_include_paths ++ pkg_include_dirs)

	    verb <- getVerbFlag
	    (md_c_flags, _) <- machdepCCOpts

	    SysTools.runCpp ([SysTools.Option verb]
			    ++ map SysTools.Option include_paths
			    ++ map SysTools.Option hs_src_cpp_opts
			    ++ map SysTools.Option hscpp_opts
			    ++ map SysTools.Option md_c_flags
			    ++ [ SysTools.Option     "-x"
			       , SysTools.Option     "c"
			       , SysTools.Option     input_fn
	-- We hackily use Option instead of FileOption here, so that the file
	-- name is not back-slashed on Windows.  cpp is capable of
	-- dealing with / in filenames, so it works fine.  Furthermore
	-- if we put in backslashes, cpp outputs #line directives
	-- with *double* backslashes.   And that in turn means that
	-- our error messages get double backslashes in them.
	-- In due course we should arrange that the lexer deals
	-- with these \\ escapes properly.
			       , SysTools.Option     "-o"
			       , SysTools.FileOption "" output_fn
			       ])
	    return (Just output_fn)

-------------------------------------------------------------------------------
-- HsPp phase 

run_phase HsPp basename suff input_fn output_fn
  = do let orig_fn = basename ++ '.':suff
       do_pp   <- dynFlag ppFlag
       if not do_pp then
           -- no need to preprocess, just pass input file along
	   -- to the next phase of the pipeline.
          return (Just input_fn)
	else do
	    hspp_opts	   <- getOpts opt_F
       	    hs_src_pp_opts <- readIORef v_Hs_source_pp_opts
	    SysTools.runPp ( [ SysTools.Option     orig_fn
			     , SysTools.Option     input_fn
			     , SysTools.FileOption "" output_fn
			     ] ++
			     map SysTools.Option hs_src_pp_opts ++
			     map SysTools.Option hspp_opts
			   )
	    return (Just output_fn)

-----------------------------------------------------------------------------
-- MkDependHS phase

run_phase MkDependHS basename suff input_fn output_fn 
 = do src <- readFile input_fn
      let (import_sources, import_normals, _) = getImports src
      let orig_fn = basename ++ '.':suff
      deps_sources <- mapM (findDependency True  orig_fn) import_sources
      deps_normals <- mapM (findDependency False orig_fn) import_normals
      let deps = deps_sources ++ deps_normals

      osuf <- readIORef v_Object_suf

      extra_suffixes <- readIORef v_Dep_suffixes
      let suffixes = osuf : map (++ ('_':osuf)) extra_suffixes
          ofiles = map (\suf -> basename ++ '.':suf) suffixes

      objs <- mapM odir_ify ofiles

	-- Handle for file that accumulates dependencies 
      hdl <- readIORef v_Dep_tmp_hdl

	-- std dependency of the object(s) on the source file
      hPutStrLn hdl (unwords (map escapeSpaces objs) ++ " : " ++
		     escapeSpaces (basename ++ '.':suff))

      let genDep (dep, False {- not an hi file -}) = 
	     hPutStrLn hdl (unwords (map escapeSpaces objs) ++ " : " ++
			    escapeSpaces dep)
          genDep (dep, True  {- is an hi file -}) = do
	     hisuf <- readIORef v_Hi_suf
	     let dep_base = remove_suffix '.' dep
	         deps = (dep_base ++ hisuf)
		        : map (\suf -> dep_base ++ suf ++ '_':hisuf) extra_suffixes
		  -- length objs should be == length deps
	     sequence_ (zipWith (\o d -> hPutStrLn hdl (escapeSpaces o ++ " : " ++ escapeSpaces d)) objs deps)

      sequence_ (map genDep [ d | Just d <- deps ])
      return (Just output_fn)

-- add the lines to dep_makefile:
	   -- always:
		   -- this.o : this.hs

  	   -- if the dependency is on something other than a .hi file:
   		   -- this.o this.p_o ... : dep
   	   -- otherwise
   		   -- if the import is {-# SOURCE #-}
   			   -- this.o this.p_o ... : dep.hi-boot[-$vers]
   			   
   		   -- else
   			   -- this.o ...   : dep.hi
   			   -- this.p_o ... : dep.p_hi
   			   -- ...
   
   	   -- (where .o is $osuf, and the other suffixes come from
   	   -- the cmdline -s options).
   

-----------------------------------------------------------------------------
-- Hsc phase

-- Compilation of a single module, in "legacy" mode (_not_ under
-- the direction of the compilation manager).
run_phase Hsc basename suff input_fn output_fn
  = do
	
  -- we add the current directory (i.e. the directory in which
  -- the .hs files resides) to the import path, since this is
  -- what gcc does, and it's probably what you want.
	let current_dir = directoryOf basename
	
	paths <- readIORef v_Include_paths
	writeIORef v_Include_paths (current_dir : paths)
	
  -- gather the imports and module name
        (_,_,mod_name) <- 
            if extcoreish_suffix suff
	     then do
               -- no explicit imports in ExtCore input.
	       m <- getCoreModuleName input_fn
	       return ([], [], mkModuleName m)
	     else 
  	       getImportsFromFile input_fn

  -- build a ModLocation to pass to hscMain.
	let (path,file) = splitFilenameDir basename
	(mod, location') <- mkHomeModLocation mod_name True path file suff

  -- take -ohi into account if present
	ohi <- readIORef v_Output_hi
	let location | Just fn <- ohi = location'{ ml_hi_file = fn }
		     | otherwise      = location'

  -- figure out if the source has changed, for recompilation avoidance.
  -- only do this if we're eventually going to generate a .o file.
  -- (ToDo: do when generating .hc files too?)
  --
  -- Setting source_unchanged to True means that M.o seems
  -- to be up to date wrt M.hs; so no need to recompile unless imports have
  -- changed (which the compiler itself figures out).
  -- Setting source_unchanged to False tells the compiler that M.o is out of
  -- date wrt M.hs (or M.o doesn't exist) so we must recompile regardless.
	do_recomp   <- readIORef v_Recomp
	todo        <- readIORef v_GhcMode
	expl_o_file <- readIORef v_Output_file

	let o_file -- if the -o option is given and IT IS THE OBJECT FILE FOR
		   -- THIS COMPILATION, then use that to determine if the 
		   -- source is unchanged.
		| Just x <- expl_o_file, todo == StopBefore Ln  =  x
		| otherwise = ml_obj_file location

	source_unchanged <- 
          if not (do_recomp && ( todo == DoLink || todo == StopBefore Ln ))
	     then return False
	     else do t1 <- getModificationTime (basename ++ '.':suff)
		     o_file_exists <- doesFileExist o_file
		     if not o_file_exists
		        then return False	-- Need to recompile
			else do t2 <- getModificationTime o_file
			        if t2 > t1
				  then return True
				  else return False

  -- get the DynFlags
        dyn_flags <- getDynFlags

        let dyn_flags' = dyn_flags { hscOutName = output_fn,
		   		     hscStubCOutName = basename ++ "_stub.c",
				     hscStubHOutName = basename ++ "_stub.h",
				     extCoreName = basename ++ ".hcr" }
	    hsc_env = HscEnv { hsc_mode = OneShot,
			       hsc_dflags = dyn_flags',
			       hsc_HPT    = emptyHomePackageTable }
			

  -- run the compiler!
        pcs <- initPersistentCompilerState
	result <- hscMain hsc_env pcs mod
			  location{ ml_hspp_file=Just input_fn }
			  source_unchanged
			  False
			  Nothing	 -- no iface

	case result of {

	    HscFail pcs -> throwDyn (PhaseFailed "hsc" (ExitFailure 1));

            HscNoRecomp pcs details iface -> do { SysTools.touch "Touching object file" o_file
						; return Nothing } ;

	    HscRecomp _pcs _details _iface stub_h_exists stub_c_exists
		      _maybe_interpreted_code -> do

			    -- deal with stubs
			    maybe_stub_o <- compileStub dyn_flags' stub_c_exists
		  	    case maybe_stub_o of
		 	      Nothing -> return ()
		 	      Just stub_o -> add v_Ld_inputs stub_o
			    case hscLang dyn_flags of
                              HscNothing -> return Nothing
			      _ -> return (Just output_fn)
    }

-----------------------------------------------------------------------------
-- Cc phase

-- we don't support preprocessing .c files (with -E) now.  Doing so introduces
-- way too many hacks, and I can't say I've ever used it anyway.

run_phase cc_phase basename suff input_fn output_fn
   | cc_phase == Cc || cc_phase == HCc
   = do	cc_opts		     <- getOpts opt_c
       	cmdline_include_paths <- readIORef v_Include_paths

        let hcc = cc_phase == HCc

	-- HC files have the dependent packages stamped into them
	pkgs <- if hcc then getHCFilePackages input_fn else return []

	-- add package include paths even if we're just compiling .c
	-- files; this is the Value Add(TM) that using ghc instead of
	-- gcc gives you :)
        pkg_include_dirs <- getPackageIncludePath pkgs
        let include_paths = foldr (\ x xs -> "-I" : x : xs) []
			      (cmdline_include_paths ++ pkg_include_dirs)

	mangle <- readIORef v_Do_asm_mangling
	(md_c_flags, md_regd_c_flags) <- machdepCCOpts

        verb <- getVerbFlag

	o2 <- readIORef v_minus_o2_for_C
	let opt_flag | o2        = "-O2"
		     | otherwise = "-O"

	pkg_extra_cc_opts <- getPackageExtraCcOpts pkgs

	split_objs <- readIORef v_Split_object_files
	let split_opt | hcc && split_objs = [ "-DUSE_SPLIT_MARKERS" ]
		      | otherwise         = [ ]

	excessPrecision <- readIORef v_Excess_precision

	-- force the C compiler to interpret this file as C when
	-- compiling .hc files, by adding the -x c option.
	let langopt
		| cc_phase == HCc = [ SysTools.Option "-x", SysTools.Option "c"]
		| otherwise       = [ ]

	SysTools.runCc (langopt ++
			[ SysTools.FileOption "" input_fn
			, SysTools.Option "-o"
			, SysTools.FileOption "" output_fn
			]
		       ++ map SysTools.Option (
		          md_c_flags
		       ++ (if cc_phase == HCc && mangle
		  	     then md_regd_c_flags
		  	     else [])
		       ++ [ verb, "-S", "-Wimplicit", opt_flag ]
		       ++ [ "-D__GLASGOW_HASKELL__="++cProjectVersionInt ]
		       ++ cc_opts
		       ++ split_opt
		       ++ (if excessPrecision then [] else [ "-ffloat-store" ])
		       ++ include_paths
		       ++ pkg_extra_cc_opts
		       ))
	return (Just output_fn)

	-- ToDo: postprocess the output from gcc

-----------------------------------------------------------------------------
-- Mangle phase

run_phase Mangle _basename _suff input_fn output_fn
  = do mangler_opts <- getOpts opt_m
       machdep_opts <- if (prefixMatch "i386" cTARGETPLATFORM)
		       then do n_regs <- dynFlag stolen_x86_regs
			       return [ show n_regs ]
		       else return []

       SysTools.runMangle (map SysTools.Option mangler_opts
		          ++ [ SysTools.FileOption "" input_fn
			     , SysTools.FileOption "" output_fn
			     ]
			  ++ map SysTools.Option machdep_opts)
       return (Just output_fn)

-----------------------------------------------------------------------------
-- Splitting phase

run_phase SplitMangle _basename _suff input_fn output_fn
  = do  -- tmp_pfx is the prefix used for the split .s files
	-- We also use it as the file to contain the no. of split .s files (sigh)
	split_s_prefix <- SysTools.newTempName "split"
	let n_files_fn = split_s_prefix

	SysTools.runSplit [ SysTools.FileOption "" input_fn
			  , SysTools.FileOption "" split_s_prefix
			  , SysTools.FileOption "" n_files_fn
			  ]

	-- Save the number of split files for future references
	s <- readFile n_files_fn
	let n_files = read s :: Int
	writeIORef v_Split_info (split_s_prefix, n_files)

	-- Remember to delete all these files
	addFilesToClean [ split_s_prefix ++ "__" ++ show n ++ ".s"
			| n <- [1..n_files]]

	return (Just output_fn)

-----------------------------------------------------------------------------
-- As phase

run_phase As _basename _suff input_fn output_fn
  = do	as_opts		      <- getOpts opt_a
        cmdline_include_paths <- readIORef v_Include_paths

	SysTools.runAs (map SysTools.Option as_opts
		       ++ [ SysTools.Option ("-I" ++ p) | p <- cmdline_include_paths ]
		       ++ [ SysTools.Option "-c"
		          , SysTools.FileOption "" input_fn
			  , SysTools.Option "-o"
			  , SysTools.FileOption "" output_fn
			  ])
	return (Just output_fn)

run_phase SplitAs basename _suff _input_fn output_fn
  = do  as_opts <- getOpts opt_a

	(split_s_prefix, n) <- readIORef v_Split_info

	odir <- readIORef v_Output_dir
	let real_odir = case odir of
				Nothing -> basename ++ "_split"
				Just d  -> d

	let assemble_file n
	      = do  let input_s  = split_s_prefix ++ "__" ++ show n ++ ".s"
		    let output_o = replaceFilenameDirectory
					(basename ++ "__" ++ show n ++ ".o")
					 real_odir
		    real_o <- osuf_ify output_o
		    SysTools.runAs (map SysTools.Option as_opts ++
		    		    [ SysTools.Option "-c"
				    , SysTools.Option "-o"
				    , SysTools.FileOption "" real_o
				    , SysTools.FileOption "" input_s
				    ])
	
	mapM_ assemble_file [1..n]
	return (Just output_fn)

#ifdef ILX
-----------------------------------------------------------------------------
-- Ilx2Il phase
-- Run ilx2il over the ILX output, getting an IL file

run_phase Ilx2Il _basename _suff input_fn output_fn
  = do	ilx2il_opts <- getOpts opt_I
        SysTools.runIlx2il (map SysTools.Option ilx2il_opts
                           ++ [ SysTools.Option "--no-add-suffix-to-assembly",
				SysTools.Option "mscorlib",
				SysTools.Option "-o",
				SysTools.FileOption "" output_fn,
				SysTools.FileOption "" input_fn ])
	return (Just output_fn)

-----------------------------------------------------------------------------
-- Ilasm phase
-- Run ilasm over the IL, getting a DLL

run_phase Ilasm _basename _suff input_fn output_fn
  = do	ilasm_opts <- getOpts opt_i
        SysTools.runIlasm (map SysTools.Option ilasm_opts
		           ++ [ SysTools.Option "/QUIET",
				SysTools.Option "/DLL",
				SysTools.FileOption "/OUT=" output_fn,
				SysTools.FileOption "" input_fn ])
	return (Just output_fn)

#endif -- ILX

-----------------------------------------------------------------------------
-- MoveBinary sort-of-phase
-- After having produced a binary, move it somewhere else and generate a
-- wrapper script calling the binary. Currently, we need this only in 
-- a parallel way (i.e. in GUM), because PVM expects the binary in a
-- central directory.
-- This is called from staticLink below, after linking. I haven't made it
-- a separate phase to minimise interfering with other modules, and
-- we don't need the generality of a phase (MoveBinary is always
-- done after linking and makes only sense in a parallel setup)   -- HWL

run_phase_MoveBinary input_fn
  = do	
        sysMan   <- getSysMan
        pvm_root <- getEnv "PVM_ROOT"
        pvm_arch <- getEnv "PVM_ARCH"
        let 
           pvm_executable_base = "=" ++ input_fn
           pvm_executable = pvm_root ++ "/bin/" ++ pvm_arch ++ "/" ++ pvm_executable_base
        -- nuke old binary; maybe use configur'ed names for cp and rm?
        system ("rm -f " ++ pvm_executable)
        -- move the newly created binary into PVM land
        system ("cp -p " ++ input_fn ++ " " ++ pvm_executable)
        -- generate a wrapper script for running a parallel prg under PVM
        writeFile input_fn (mk_pvm_wrapper_script pvm_executable pvm_executable_base sysMan)
	return True

-- generates a Perl skript starting a parallel prg under PVM
mk_pvm_wrapper_script :: String -> String -> String -> String
mk_pvm_wrapper_script pvm_executable pvm_executable_base sysMan = unlines $
 [
  "eval 'exec perl -S $0 ${1+\"$@\"}'", 
  "  if $running_under_some_shell;",
  "# =!=!=!=!=!=!=!=!=!=!=!",
  "# This script is automatically generated: DO NOT EDIT!!!",
  "# Generated by Glasgow Haskell Compiler",
  "# ngoqvam choHbogh vaj' vIHoHnISbej !!!!",
  "#",
  "$pvm_executable      = '" ++ pvm_executable ++ "';",
  "$pvm_executable_base = '" ++ pvm_executable_base ++ "';",
  "$SysMan = '" ++ sysMan ++ "';",
  "",
  {- ToDo: add the magical shortcuts again iff we actually use them -- HWL
  "# first, some magical shortcuts to run "commands" on the binary",
  "# (which is hidden)",
  "if ($#ARGV == 1 && $ARGV[0] eq '+RTS' && $ARGV[1] =~ /^--((size|file|strip|rm|nm).*)/ ) {",
  "    local($cmd) = $1;",
  "    system("$cmd $pvm_executable");",
  "    exit(0); # all done",
  "}", -}
  "",
  "# Now, run the real binary; process the args first",
  "$ENV{'PE'} = $pvm_executable_base;", --  ++ pvm_executable_base,
  "$debug = '';",
  "$nprocessors = 0; # the default: as many PEs as machines in PVM config",
  "@nonPVM_args = ();",
  "$in_RTS_args = 0;",
  "",
  "args: while ($a = shift(@ARGV)) {",
  "    if ( $a eq '+RTS' ) {",
  "	$in_RTS_args = 1;",
  "    } elsif ( $a eq '-RTS' ) {",
  "	$in_RTS_args = 0;",
  "    }",
  "    if ( $a eq '-d' && $in_RTS_args ) {",
  "	$debug = '-';",
  "    } elsif ( $a =~ /^-qN(\\d+)/ && $in_RTS_args ) {",
  "	$nprocessors = $1;",
  "    } elsif ( $a =~ /^-qp(\\d+)/ && $in_RTS_args ) {",
  "	$nprocessors = $1;",
  "    } else {",
  "	push(@nonPVM_args, $a);",
  "    }",
  "}",
  "",
  "local($return_val) = 0;",
  "# Start the parallel execution by calling SysMan",
  "system(\"$SysMan $debug $pvm_executable $nprocessors @nonPVM_args\");",
  "$return_val = $?;",
  "# ToDo: fix race condition moving files and flushing them!!",
  "system(\"cp $ENV{'HOME'}/$pvm_executable_base.???.gr .\") if -f \"$ENV{'HOME'}/$pvm_executable_base.002.gr\";",
  "exit($return_val);"
 ]

-----------------------------------------------------------------------------
-- Complain about non-dynamic flags in OPTIONS pragmas

checkProcessArgsResult flags basename suff
  = do when (notNull flags) (throwDyn (ProgramError (
	  showSDoc (hang (text basename <> text ('.':suff) <> char ':')
		      4 (text "unknown flags in  {-# OPTIONS #-} pragma:" <+>
			  hsep (map text flags)))
	)))

-----------------------------------------------------------------------------
-- Look for the /* GHC_PACKAGES ... */ comment at the top of a .hc file

getHCFilePackages :: FilePath -> IO [PackageName]
getHCFilePackages filename =
  EXCEPTION.bracket (openFile filename ReadMode) hClose $ \h -> do
    l <- hGetLine h
    case l of
      '/':'*':' ':'G':'H':'C':'_':'P':'A':'C':'K':'A':'G':'E':'S':rest ->
	  return (map mkPackageName (words rest))
      _other ->
	  return []

-----------------------------------------------------------------------------
-- Static linking, of .o files

-- The list of packages passed to link is the list of packages on
-- which this program depends, as discovered by the compilation
-- manager.  It is combined with the list of packages that the user
-- specifies on the command line with -package flags.  
--
-- In one-shot linking mode, we can't discover the package
-- dependencies (because we haven't actually done any compilation or
-- read any interface files), so the user must explicitly specify all
-- the packages.

staticLink :: [FilePath] -> [PackageName] -> IO ()
staticLink o_files dep_packages = do
    verb       <- getVerbFlag
    static     <- readIORef v_Static
    no_hs_main <- readIORef v_NoHsMain

    -- get the full list of packages to link with, by combining the
    -- explicit packages with the auto packages and all of their
    -- dependencies, and eliminating duplicates.

    o_file <- readIORef v_Output_file
    let output_fn = case o_file of { Just s -> s; Nothing -> "a.out"; }

    pkg_lib_paths <- getPackageLibraryPath dep_packages
    let pkg_lib_path_opts = map ("-L"++) pkg_lib_paths

    lib_paths <- readIORef v_Library_paths
    let lib_path_opts = map ("-L"++) lib_paths

    pkg_link_opts <- getPackageLinkOpts dep_packages

#ifdef darwin_TARGET_OS
    pkg_framework_paths <- getPackageFrameworkPath dep_packages
    let pkg_framework_path_opts = map ("-F"++) pkg_framework_paths

    framework_paths <- readIORef v_Framework_paths
    let framework_path_opts = map ("-F"++) framework_paths

    pkg_frameworks <- getPackageFrameworks dep_packages
    let pkg_framework_opts = concat [ ["-framework", fw] | fw <- pkg_frameworks ]

    frameworks <- readIORef v_Cmdline_frameworks
    let framework_opts = concat [ ["-framework", fw] | fw <- reverse frameworks ]
	 -- reverse because they're added in reverse order from the cmd line
#endif

	-- probably _stub.o files
    extra_ld_inputs <- readIORef v_Ld_inputs

	-- opts from -optl-<blah> (including -l<blah> options)
    extra_ld_opts <- getStaticOpts v_Opt_l

    [rts_pkg, std_pkg] <- getPackageDetails [rtsPackage, basePackage]

    let extra_os = if static || no_hs_main
                   then []
                   else [ head (library_dirs rts_pkg) ++ "/Main.dll_o",
                          head (library_dirs std_pkg) ++ "/PrelMain.dll_o" ]

    (md_c_flags, _) <- machdepCCOpts
    SysTools.runLink ( [ SysTools.Option verb
    		       , SysTools.Option "-o"
		       , SysTools.FileOption "" output_fn
		       ]
		      ++ map SysTools.Option (
		         md_c_flags
	 	      ++ o_files
		      ++ extra_os
		      ++ extra_ld_inputs
	 	      ++ lib_path_opts
	 	      ++ extra_ld_opts
#ifdef darwin_TARGET_OS
	 	      ++ framework_path_opts
	 	      ++ framework_opts
#endif
	 	      ++ pkg_lib_path_opts
	 	      ++ pkg_link_opts
#ifdef darwin_TARGET_OS
	 	      ++ pkg_framework_path_opts
	 	      ++ pkg_framework_opts
#endif
	              ++ if static && not no_hs_main then
			    [ "-u", prefixUnderscore "Main_zdmain_closure"] 
			 else []))

    -- parallel only: move binary to another dir -- HWL
    ways_ <- readIORef v_Ways
    when (WayPar `elem` ways_)
	 (do success <- run_phase_MoveBinary output_fn
             if success then return ()
                        else throwDyn (InstallationError ("cannot move binary to PVM dir")))

-----------------------------------------------------------------------------
-- Making a DLL (only for Win32)

doMkDLL :: [String] -> IO ()
doMkDLL o_files = do
    verb       <- getVerbFlag
    static     <- readIORef v_Static
    no_hs_main <- readIORef v_NoHsMain

    o_file <- readIORef v_Output_file
    let output_fn = case o_file of { Just s -> s; Nothing -> "HSdll.dll"; }

    pkg_lib_paths <- getPackageLibraryPath []
    let pkg_lib_path_opts = map ("-L"++) pkg_lib_paths

    lib_paths <- readIORef v_Library_paths
    let lib_path_opts = map ("-L"++) lib_paths

    pkg_link_opts <- getPackageLinkOpts []

	-- probably _stub.o files
    extra_ld_inputs <- readIORef v_Ld_inputs

	-- opts from -optdll-<blah>
    extra_ld_opts <- getStaticOpts v_Opt_dll

    [rts_pkg, std_pkg] <- getPackageDetails [rtsPackage, basePackage]

    let extra_os = if static || no_hs_main
                   then []
                   else [ head (library_dirs rts_pkg) ++ "/Main.dll_o",
                          head (library_dirs std_pkg) ++ "/PrelMain.dll_o" ]

    (md_c_flags, _) <- machdepCCOpts
    SysTools.runMkDLL
	 ([ SysTools.Option verb
	  , SysTools.Option "-o"
	  , SysTools.FileOption "" output_fn
	  ]
	 ++ map SysTools.Option (
	    md_c_flags
	 ++ o_files
	 ++ extra_os
	 ++ [ "--target=i386-mingw32" ]
	 ++ extra_ld_inputs
	 ++ lib_path_opts
	 ++ extra_ld_opts
	 ++ pkg_lib_path_opts
	 ++ pkg_link_opts
         ++ (if "--def" `elem` (concatMap words extra_ld_opts)
	       then [ "" ]
               else [ "--export-all" ])
	))
