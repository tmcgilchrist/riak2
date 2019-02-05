module Riak.Interface.Impl.Socket.Concurrent
  ( Interface
  , Config
  , EventHandlers(..)
  , withInterface
  , exchange
  , stream
  ) where

import Control.Concurrent.MVar
import Data.Coerce             (coerce)
import Riak.Request            (Request)
import Riak.Response           (Response)
import Riak.Socket             (Socket)
import UnliftIO.Exception      (bracket_, finally)

import qualified Riak.Socket as Socket


data Interface
  = Interface
  { socket :: !Socket
  , sync :: !Synchronized
  , relay :: !Relay
  , handlers :: !EventHandlers
  }

data Config
  = Config
  { socket :: !Socket
  , handlers :: !EventHandlers
  }

data EventHandlers
  = EventHandlers
  { onSend :: Request -> IO ()
  , onReceive :: Maybe Response -> IO ()
  }

instance Monoid EventHandlers where
  mempty = EventHandlers mempty mempty
  mappend = (<>)

instance Semigroup EventHandlers where
  EventHandlers a1 b1 <> EventHandlers a2 b2 =
    EventHandlers (a1 <> a2) (b1 <> b2)


withInterface ::
     Config -- ^
  -> (Interface -> IO a) -- ^
  -> IO a
withInterface Config { socket, handlers } k = do
  sync :: Synchronized <-
    newSynchronized

  relay :: Relay <-
    newRelay

  bracket_
    (Socket.connect socket)
    (Socket.disconnect socket)
    (k Interface
      { socket = socket
      , sync = sync
      , relay = relay
      , handlers = handlers
      })

exchange ::
     Interface
  -> Request
  -> IO (Maybe Response)
exchange Interface { socket, sync, relay, handlers } request = do
  baton :: Baton <-
    synchronized sync $ do
      onSend handlers request
      Socket.send socket request
      enterRelay relay

  response :: Maybe Response <-
    withBaton baton (Socket.receive socket)

  onReceive handlers response

  pure response

stream ::
     Interface
  -> Request
  -> (IO (Maybe Response) -> IO r)
  -> IO r
stream Interface { socket, sync, relay, handlers } request callback =
  -- Riak request handling state machine is odd. Streaming responses are
  -- special; when one is active, no other requests can be serviced on this
  -- socket. I learned this the hard way by reading Riak source code.
  --
  -- So, hold a lock for the entirety of the request-response exchange, not just
  -- during sending the request.
  synchronized sync $ do
    onSend handlers request
    Socket.send socket request

    callback $ do
      response :: Maybe Response <-
        Socket.receive socket
      onReceive handlers response
      pure response


newtype Synchronized
  = Synchronized (MVar ())

newSynchronized :: IO Synchronized
newSynchronized =
  coerce (newMVar ())

synchronized :: Synchronized -> IO a -> IO a
synchronized (Synchronized var) =
  withMVar var . const


newtype Relay
  = Relay (MVar (MVar ()))

data Baton
  = Baton (MVar ()) (MVar ())

newRelay :: IO Relay
newRelay =
  coerce (newMVar =<< newMVar ())

enterRelay :: Relay -> IO Baton
enterRelay (Relay var) = do
  after <- newEmptyMVar
  before <- swapMVar var after
  pure (Baton before after)

-- TODO think about async exceptions a bit here
withBaton :: Baton -> IO a -> IO a
withBaton (Baton before after) action = do
  takeMVar before
  action `finally` putMVar after ()
