{-# LANGUAGE LambdaCase, OverloadedStrings, PatternSynonyms, ViewPatterns #-}

import Control.Concurrent
import Control.Concurrent.MVar
import Control.Monad
import Data.Text          (Text)
import Riak
import System.Environment
import Text.Read          (readMaybe)

main :: IO ()
main = do
  getArgs >>= \case
    [readMaybe -> Just n, readMaybe -> Just i] -> do
      putStrLn $
        "Putting " ++ show n ++ " objects with " ++ show i ++ " threads"

      h <- createRiakHandle "10.0.0.16" 8087

      let
        go =
          replicateM_ (n `div` i) $ do
            Right _ <-
              putNewRiakObject h
                (DefaultRiakBucket "foo")
                ("bar" :: Text)
                def
            pure ()

      done <- newEmptyMVar
      replicateM_ i $ forkIO $ go >> putMVar done ()
      replicateM_ i $ takeMVar done

    _ ->
      putStrLn "Usage: run-benchmark put OBJECTS THREADS"
