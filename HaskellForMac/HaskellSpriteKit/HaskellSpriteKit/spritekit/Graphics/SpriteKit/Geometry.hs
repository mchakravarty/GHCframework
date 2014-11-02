{-# LANGUAGE TemplateHaskell, QuasiQuotes, DeriveDataTypeable, RecordWildCards, ForeignFunctionInterface #-}

-- |
-- Module      : Graphics.SpriteKit.Geometry
-- Copyright   : [2014] Manuel M T Chakravarty
-- License     : All rights reserved
--
-- Maintainer  : Manuel M T Chakravarty <chak@justtesting.org>
-- Stability   : experimental
--
-- Geometry types and operations

module Graphics.SpriteKit.Geometry (
  GFloat, Point(..), Size(..),
  pointZero, sizeZero, 
  
  -- * Marshalling functions
  pointToCGPoint, cgPointToPoint,
  sizeToCGSize, cgSizeToSize,
  
  geometry_initialise
) where
  
  -- standard libraries
import Data.Typeable
import Foreign

  -- language-c-inline
import Language.C.Quote.ObjC
import Language.C.Inline.ObjC

objc_import ["<Cocoa/Cocoa.h>", "<SpriteKit/SpriteKit.h>", "GHC/HsFFI.h"]


-- |Graphics float (which is a 'Float' or 'Double' depending on whether we are on a 32 or 64 bit architecture)
--
type GFloat = Double      -- FIXME: need to be set in dependence on the definition of 'CGFloat' resp 'CGFLOAT_IS_DOUBLE'

-- |Point in a two-dimensional coordinate system.
--
data Point = Point {pointX :: GFloat, pointY :: GFloat}

-- |Point at (0, 0).
--
pointZero :: Point
pointZero = Point 0 0

newtype CGPoint = CGPoint (ForeignPtr CGPoint)
  deriving Typeable   -- needed for now until migrating to new TH
  -- FIXME: CGPoint and CGSize need free() as a finaliser not '-release'.
  --        How should language-c-inline distinguish? Check whether it is an object?

objc_typecheck

pointToCGPoint :: Point -> IO CGPoint
pointToCGPoint (Point {..})
  -- FIXME: language-c-inline needs to look through type synonyms
  -- = $(objc ['pointX :> ''GFloat, 'pointY :> ''GFloat] $ Class ''CGPoint <:
  = $(objc ['pointX :> ''Double, 'pointY :> ''Double] $ Class ''CGPoint <:
       [cexp| ({ 
         typename CGPoint *pnt = (typename CGPoint *) malloc(sizeof(CGPoint)); 
         *pnt = CGPointMake(pointX, pointY); 
         pnt; 
       }) |] )

cgPointToPoint :: CGPoint -> IO Point
cgPointToPoint (CGPoint pointPtr)
  = withForeignPtr pointPtr $ \pointPtr -> do
    { x <- peekElemOff (castPtr pointPtr :: Ptr GFloat) 0
    ; y <- peekElemOff (castPtr pointPtr :: Ptr GFloat) 1
    ; return $ Point x y
    }

data Size = Size {sizeWidth :: GFloat, sizeHeight :: GFloat}
  deriving Typeable

sizeZero :: Size
sizeZero = Size 0 0

newtype CGSize = CGSize (ForeignPtr CGSize)
  deriving Typeable   -- needed for now until migrating to new TH

objc_typecheck

sizeToCGSize :: Size -> IO CGSize
sizeToCGSize (Size {..})
  -- FIXME: language-c-inline needs to look through type synonyms
  -- = $(objc ['sizeWidth :> ''GFloat, 'sizeHeight :> ''GFloat] $ Class ''CGSize <:
  = $(objc ['sizeWidth :> ''Double, 'sizeHeight :> ''Double] $ Class ''CGSize <:
        [cexp| ({ 
          typename CGSize *sz = (typename CGSize *) malloc(sizeof(CGSize)); 
          *sz = CGSizeMake(sizeWidth, sizeHeight); 
          sz; 
        }) |] )

cgSizeToSize :: CGSize -> IO Size
cgSizeToSize (CGSize sizePtr)
  = withForeignPtr sizePtr $ \sizePtr -> do
    { width  <- peekElemOff (castPtr sizePtr :: Ptr GFloat) 0
    ; height <- peekElemOff (castPtr sizePtr :: Ptr GFloat) 1
    ; return $ Size width height
    }

objc_emit

geometry_initialise = objc_initialise
