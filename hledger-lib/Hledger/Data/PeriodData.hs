{-# LANGUAGE CPP #-}
{-|


Data values for zero or more report periods, and for the pre-report period.
Report periods are assumed to be contiguous, and represented only by start dates
(as keys of an IntMap).

-}
module Hledger.Data.PeriodData
( periodDataFromList

, lookupPeriodData
, insertPeriodData
, opPeriodData
, mergePeriodData
, padPeriodData

, tests_PeriodData
) where

import Data.Foldable1 (Foldable1(..))
import qualified Data.IntMap.Strict as IM
import qualified Data.IntSet as IS
#if !MIN_VERSION_base(4,20,0)
import Data.List (foldl')
#endif
import Data.Time (Day(..), fromGregorian)

import Test.Tasty (testGroup)
import Test.Tasty.HUnit ((@?=), testCase)

import Hledger.Data.Amount
import Hledger.Data.Types


instance Show a => Show (PeriodData a) where
  showsPrec d (PeriodData h ds) =
    showParen (d > 10) $
        showString "PeriodData"
      . showString "{ pdpre = " . shows h
      . showString ", pdperiods = "
      . showString "fromList " . shows (map (\(day, x) -> (ModifiedJulianDay $ toInteger day, x)) $ IM.toList ds)
      . showChar '}'

instance Foldable PeriodData where
  foldr f z (PeriodData h as) = foldr f (f h z) as
  foldl f z (PeriodData h as) = foldl f (f z h) as
  foldl' f z (PeriodData h as) = let fzh = f z h in fzh `seq` foldl' f fzh as

instance Foldable1 PeriodData where
  foldrMap1 f g (PeriodData h as) = foldr g (f h) as
  foldlMap1 f g (PeriodData h as) = foldl g (f h) as
  foldlMap1' f g (PeriodData h as) = let fh = f h in fh `seq` foldl' g fh as

instance Traversable PeriodData where
  traverse f (PeriodData h as) = liftA2 PeriodData (f h) $ traverse f as

-- | The Semigroup instance for 'AccountBalance' will simply take the union of
-- keys in the date map section. This may not be the result you want if the
-- keys are not identical.
instance Semigroup a => Semigroup (PeriodData a) where
  PeriodData h1 as1 <> PeriodData h2 as2 = PeriodData (h1 <> h2) $ IM.unionWith (<>) as1 as2

instance Monoid a => Monoid (PeriodData a) where
  mempty = PeriodData mempty mempty

-- | Construct an 'PeriodData' from a list.
periodDataFromList :: a -> [(Day, a)] -> PeriodData a
periodDataFromList h = PeriodData h . IM.fromList . map (\(d, a) -> (fromInteger $ toModifiedJulianDay d, a))

-- | Get account balance information to the period containing a given 'Day'.
lookupPeriodData :: Day -> PeriodData a -> a
lookupPeriodData d (PeriodData h as) =
    maybe h snd $ IM.lookupLE (fromInteger $ toModifiedJulianDay d) as

-- | Add account balance information to the appropriate location in 'PeriodData'.
insertPeriodData :: Semigroup a => Maybe Day -> a -> PeriodData a -> PeriodData a
insertPeriodData mday b balances = case mday of
    Nothing  -> balances{pdpre = pdpre balances <> b}
    Just day -> balances{pdperiods = IM.insertWith (<>) (fromInteger $ toModifiedJulianDay day) b $ pdperiods balances}

-- | Merges two 'PeriodData', using the given operation to combine their balance information.
--
-- This will drop keys if they are not present in both 'PeriodData'.
opPeriodData :: (a -> b -> c) -> PeriodData a -> PeriodData b -> PeriodData c
opPeriodData f (PeriodData h1 as1) (PeriodData h2 as2) =
    PeriodData (f h1 h2) $ IM.intersectionWith f as1 as2

-- | Merges two 'PeriodData', using the given operations for balance
-- information only in the first, only in the second, or in both
-- 'PeriodData', respectively.
mergePeriodData :: (a -> c) -> (b -> c) -> (a -> b -> c)
                -> PeriodData a -> PeriodData b -> PeriodData c
mergePeriodData only1 only2 f = \(PeriodData h1 as1) (PeriodData h2 as2) ->
    PeriodData (f h1 h2) $ merge as1 as2
  where
    merge = IM.mergeWithKey (\_ x y -> Just $ f x y) (fmap only1) (fmap only2)

-- | Pad out the datemap of an 'PeriodData' so that every key from a set is present.
padPeriodData :: Monoid a => IS.IntSet -> PeriodData a -> PeriodData a
padPeriodData keys bal = bal{pdperiods = pdperiods bal <> IM.fromSet (const mempty) keys}


-- tests

tests_PeriodData =
  let
    dayMap  = periodDataFromList (mixed [usd 1]) [(fromGregorian 2000 01 01, mixed [usd 2]), (fromGregorian 2004 02 28, mixed [usd 3])]
    dayMap2 = periodDataFromList (mixed [usd 2]) [(fromGregorian 2000 01 01, mixed [usd 4]), (fromGregorian 2004 02 28, mixed [usd 6])]
  in testGroup "PeriodData" [

  testCase "periodDataFromList" $ do
    length dayMap @?= 3,

  testCase "Semigroup instance" $ do
    dayMap <> dayMap @?= dayMap2,

  testCase "Monoid instance" $ do
    dayMap <> mempty @?= dayMap
  ]
