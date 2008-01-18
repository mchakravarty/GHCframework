{-# LANGUAGE RankNTypes, ScopedTypeVariables #-}
module Language.Haskell.TH.Quasi(
	QuasiQuoter(..),
        dataToQa, dataToExpQ, dataToPatQ
    ) where

import Data.Generics
import Language.Haskell.TH.Lib
import Language.Haskell.TH.Syntax

data QuasiQuoter = QuasiQuoter { quoteExp :: String -> Q Exp,
                                 quotePat :: String -> Q Pat }

dataToQa  ::  forall a k q. Data a
          =>  (Name -> k)
          ->  (Lit -> Q q)
          ->  (k -> [Q q] -> Q q)
          ->  (forall a . Data a => a -> Maybe (Q q))
          ->  a
          ->  Q q
dataToQa mkCon mkLit appCon antiQ t =
    case antiQ t of
      Nothing ->
          case constrRep constr of
            AlgConstr _  ->
                appCon con conArgs
            IntConstr n ->
                mkLit $ integerL n
            FloatConstr n ->
                mkLit $ rationalL (toRational n)
            StringConstr (c:_) ->
                mkLit $ charL c
        where
          constr :: Constr
          constr = toConstr t
          constrName :: Constr -> String
          constrName k =
              case showConstr k of
                "(:)"  -> ":"
                name   -> name
          con :: k
          con = mkCon (mkName (constrName constr))
          conArgs :: [Q q]
          conArgs = gmapQ (dataToQa mkCon mkLit appCon antiQ) t

      Just y -> y

-- | 'dataToExpQ' converts a value to a 'Q Exp' representation of the same
-- value. It takes a function to handle type-specific cases.
dataToExpQ  ::  Data a
            =>  (forall a . Data a => a -> Maybe (Q Exp))
            ->  a
            ->  Q Exp
dataToExpQ = dataToQa conE litE (foldl appE)

-- | 'dataToPatQ' converts a value to a 'Q Pat' representation of the same
-- value. It takes a function to handle type-specific cases.
dataToPatQ  ::  Data a
            =>  (forall a . Data a => a -> Maybe (Q Pat))
            ->  a
            ->  Q Pat
dataToPatQ = dataToQa id litP conP
