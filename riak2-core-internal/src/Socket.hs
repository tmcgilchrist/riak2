module Socket
  ( Socket(..)
    -- TODO better new1/new2/new3 names
  , new1
  , new2
  , new3
  , connect
  , disconnect
  , send
  , receive
  ) where

import Data.Bits         (shiftL, (.|.))
import Data.ByteString   (ByteString)
import Data.Int          (Int32)
import Data.IORef

import qualified Data.Attoparsec.ByteString as Atto
import qualified Data.ByteString            as ByteString
import qualified Network.Socket             as Network hiding (recv)
import qualified Network.Socket.ByteString  as Network (recv, sendAll)

data Socket
  = Socket Network.Socket Network.SockAddr (IORef ByteString)

new1 ::
     Network.HostName
  -> Network.PortNumber
  -> IO Socket
new1 host port = do
  info : _ <-
    let
      hints =
        Network.defaultHints { Network.addrSocketType = Network.Stream }
    in
      Network.getAddrInfo (Just hints) (Just host) (Just (show port))

  new2 info

new2 ::
     Network.AddrInfo -- ^
  -> IO Socket
new2 info = do
  socket :: Network.Socket <-
    Network.socket
      (Network.addrFamily info)
      (Network.addrSocketType info)
      (Network.addrProtocol info)

  new3 socket (Network.addrAddress info)

new3 ::
     Network.Socket -- ^
  -> Network.SockAddr -- ^
  -> IO Socket
new3 socket addr = do
  bufferRef :: IORef ByteString <-
    newIORef ByteString.empty
  pure (Socket socket addr bufferRef)

connect :: Socket -> IO ()
connect (Socket socket addr _) =
  Network.connect socket addr

disconnect :: Socket -> IO ()
disconnect (Socket socket _ bufferRef) = do
  writeIORef bufferRef ByteString.empty
  Network.close socket

receive :: Socket -> IO (Maybe ByteString)
receive (Socket socket _ bufferRef) = do
  buffer <- readIORef bufferRef

  loop
    (if ByteString.null buffer
      then Atto.Partial parse
      else parse buffer)

  where
    loop :: Atto.IResult ByteString ByteString -> IO (Maybe ByteString)
    loop = \case
      -- The response parser is just a 4-byte length followed by that many
      -- bytes, so just assume that can only fail due to not enough bytes.
      Atto.Fail _unconsumed _context _reason ->
        pure Nothing

      Atto.Partial k -> do
        bytes <- Network.recv socket 16384

        loop
          (if ByteString.null bytes
            then k ByteString.empty
            else parse bytes)

      Atto.Done unconsumed response -> do
        writeIORef bufferRef unconsumed
        pure (Just response)

parse :: ByteString -> Atto.IResult ByteString ByteString
parse =
  Atto.parse parser

parser :: Atto.Parser ByteString
parser = do
  len <- int32be
  Atto.take (fromIntegral len)

  where
    -- | Attoparsec parser for a 32-bit big-endian integer.
    int32be :: Atto.Parser Int32
    int32be = do
      w0 <- Atto.anyWord8
      w1 <- Atto.anyWord8
      w2 <- Atto.anyWord8
      w3 <- Atto.anyWord8
      pure $
        shiftL (fromIntegral w0) 24 .|.
        shiftL (fromIntegral w1) 16 .|.
        shiftL (fromIntegral w2)  8 .|.
                fromIntegral w3

send :: Socket -> ByteString -> IO ()
send (Socket socket _ _) bytes =
  Network.sendAll socket bytes