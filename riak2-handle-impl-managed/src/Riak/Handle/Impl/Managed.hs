-- | A Riak client that manages another client by reconnecting automatically.
--
-- Still TODO: some way of configuring when we want to reconnect, and when we
-- want to give up on the connection permanently.

module Riak.Handle.Impl.Managed
  ( Handle
  , Config
  , withHandle
  , exchange
  , stream
  , Error(..)
  ) where

import Riak.Request  (Request)
import Riak.Response (Response)

import qualified Riak.Handle.Signature as Handle

import Control.Concurrent
import Control.Concurrent.STM
import Control.Exception      (asyncExceptionFromException,
                               asyncExceptionToException)
import Control.Exception.Safe (Exception(..), SomeException, bracket, catchAny)
import Control.Monad          (when)
import Foreign.C              (CInt)
import Numeric.Natural        (Natural)


data Handle
  = Handle
  { handleVar :: !(TMVar (Handle.Handle, Natural))
    -- ^ The handle, and which "generation" it is (when 0 dies, 1 replaces it,
    -- etc.
  , errorVar :: !(TMVar Handle.Error)
    -- ^ The last error some client received when trying to use the handle.
  }

type Config
  = Handle.Config

data Error
  = Error
  deriving stock (Eq, Show)

data HandleCrashed
  = HandleCrashed SomeException
  deriving stock (Show)

instance Exception HandleCrashed where
  toException = asyncExceptionToException
  fromException = asyncExceptionFromException

-- | Acquire a handle.
--
-- /Throws/. Whatever the underlying handle might throw during its 'withHandle'.
--
-- /Throws/. If the background manager thread crashes, throws an asynchronous
-- 'HandleCrashed' exception.
withHandle ::
     Config
  -> (Handle -> IO a)
  -> IO (Either CInt a)
withHandle config k = do
  handleVar :: TMVar (Handle.Handle, Natural) <-
    newEmptyTMVarIO

  errorVar :: TMVar Handle.Error <-
    newEmptyTMVarIO

  threadId :: ThreadId <-
    myThreadId

  bracket
    (forkIOWithUnmask $ \unmask ->
      unmask (manager config handleVar errorVar) `catchAny` \e ->
        throwTo threadId (HandleCrashed e))
    killThread
    (\_ ->
      Right <$>
        k Handle
          { handleVar = handleVar
          , errorVar = errorVar
          })

-- The manager thread:
--
-- * Acquire an underlying connection.
-- * Smuggle it out to the rest of the world via a TMVar.
-- * Wait for an error to appear in another TMVar, then reconnect.
--
-- Meanwhile, users of this handle (via exchange/stream) grab the underlying
-- handle (if available), use it, and if anything goes wrong, write to the error
-- TMVar and retry when a new connection is established.
manager ::
     Config
  -> TMVar (Handle.Handle, Natural)
  -> TMVar Handle.Error
  -> IO a
manager config handleVar errorVar =
  loop 0

  where
    loop :: Natural -> IO a
    loop !generation =
      Handle.withHandle config runUntilError >>= \case
        Left connectErr -> do
          putStrLn ("Manager thread (dis)connect error: " ++ show connectErr)

          -- Annoying... withHandle disconnecting on a broken socket connection
          -- is hiding the actual handle error that caused it. Whatever, read it
          -- out of the TMVar.
          atomically (tryReadTMVar errorVar) >>= \case
            Nothing -> putStrLn "Manager thread handle error: <none>"
            Just handleErr -> putStrLn ("Manager thread handle error: " ++ show handleErr)

          threadDelay 1000000
          loop (generation+1)

        Right handleErr -> do
          putStrLn ("Manager thread handle error: " ++ show handleErr)
          threadDelay 1000000
          loop (generation+1)

      where
        runUntilError :: Handle.Handle -> IO Handle.Error
        runUntilError handle = do
          -- Clear out any previous errors, and put the healthy handle for
          -- clients to use
          atomically $ do
            _ <- tryTakeTMVar errorVar
            putTMVar handleVar (handle, generation)

          -- When a client records an error, remove the handle so no more
          -- clients use it (don't bother clearing out the error var yet)
          atomically $ do
            err <- readTMVar errorVar
            _ <- takeTMVar handleVar
            pure err

-- | Send a request and receive the response (a single message).
exchange ::
     Handle
  -> Request
  -> IO (Either Error Response)
exchange Handle { handleVar, errorVar } request =
  loop 0

  where
    loop :: Natural -> IO (Either Error Response)
    loop !healthyGen = do
      (handle, gen) <-
        waitForGen healthyGen handleVar

      Handle.exchange handle request >>= \case
        Left err -> do
          -- Notify the manager thread of an error (try put, because it's ok
          -- if we are not the first thread to do so)
          _ <- atomically (tryPutTMVar errorVar err)

          -- Try again once the connection is re-established.
          loop (gen + 1)

        Right response ->
          pure (Right response)

-- | Send a request and stream the response (one or more messages).
stream ::
     ∀ r x.
     Handle -- ^
  -> Request -- ^
  -> x
  -> (x -> Response -> IO (Either x r))
  -> IO (Either Error r)
stream Handle { handleVar, errorVar } request value step =
  loop 0

  where
    loop :: Natural -> IO (Either Error r)
    loop !healthyGen = do
      (handle, gen) <-
        waitForGen healthyGen handleVar

      Handle.stream handle request value step >>= \case
        Left err -> do
          -- Notify the manager thread of an error (try put, because it's ok
          -- if we are not the first thread to do so)
          _ <- atomically (tryPutTMVar errorVar err)

          -- Try again once the connection is re-established.
          loop (gen + 1)

        Right response ->
          pure (Right response)

-- Wait for (at least) the given generation of handle.
waitForGen ::
     Natural
  -> TMVar (Handle.Handle, Natural)
  -> IO (Handle.Handle, Natural)
waitForGen healthyGen handleVar =
  atomically $ do
    (handle, gen) <- readTMVar handleVar
    when (gen < healthyGen) retry
    pure (handle, gen)
