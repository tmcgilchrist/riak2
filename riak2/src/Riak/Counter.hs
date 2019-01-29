module Riak.Counter
  ( Counter(..)
  , get
  , update
  ) where

import Riak.Internal.Client  (Client, Result(..))
import Riak.Internal.Prelude
import Riak.Key              (Key(..))

import qualified Riak.Internal.Client as Client
import qualified Riak.Proto           as Proto
import qualified Riak.Proto.Lens      as L

import qualified Data.ByteString as ByteString


-- | A counter data type.
--
-- Counters must be stored in a bucket type with the __@datatype = counter@__
-- property.
--
-- /Note/: Counters do not contain a causal context, so it is not necessary to
-- read a counter before updating it.
data Counter
  = Counter
  { key :: !Key -- ^
  , value :: !Int64 -- ^
  } deriving stock (Generic, Show)

-- | Get a counter.
get ::
     MonadIO m
  => Client -- ^
  -> Key -- ^
  -> m (Result (Maybe Counter))
get client k@(Key type' bucket key) = liftIO $
  (fmap.fmap)
    fromResponse
    (Client.getCrdt client request)

  where
    request :: Proto.GetCrdtRequest
    request =
      defMessage
        & L.bucket .~ bucket
        & L.key .~ key
        & L.type' .~ type'

        -- TODO get counter opts
        -- & L.maybe'basicQuorum .~ undefined
        -- & L.maybe'nVal .~ undefined
        -- & L.maybe'notfoundOk .~ undefined
        -- & L.maybe'pr .~ undefined
        -- & L.maybe'r .~ undefined
        -- & L.maybe'sloppyQuorum .~ undefined
        -- & L.maybe'timeout .~ undefined

    fromResponse :: Proto.GetCrdtResponse -> Maybe Counter
    fromResponse response = do
      crdt :: Proto.Crdt <-
        response ^. L.maybe'value
      pure Counter
        { key = k
        , value = crdt ^. L.counter
        }

-- | Update a counter.
--
-- /Note/: Counters, unlike other data types, represent their own update
-- operation.
--
-- /See also/: @Riak.Key.'Riak.Key.none'@
update ::
     MonadIO m
  => Client -- ^
  -> Counter -- ^
  -> m (Result Counter)
update client (Counter { key, value }) = liftIO $
  (fmap.fmap)
    fromResponse
    (Client.updateCrdt client request)

  where
    request :: Proto.UpdateCrdtRequest
    request =
      defMessage
        & L.bucket .~ bucket
        & L.maybe'key .~
            (if ByteString.null k
              then Nothing
              else Just k)
        & L.update .~
            -- Missing value defaults to 1, so don't bother sending it
            case value of
              1 ->
                defMessage

              _ ->
                defMessage
                  & L.counterUpdate .~
                      (defMessage
                        & L.increment .~ value)
        & L.returnBody .~ True
        & L.type' .~ type'
-- TODO counter update opts
-- _DtUpdateReq'w :: !(Prelude.Maybe Data.Word.Word32),
-- _DtUpdateReq'dw :: !(Prelude.Maybe Data.Word.Word32),
-- _DtUpdateReq'pw :: !(Prelude.Maybe Data.Word.Word32),
-- _DtUpdateReq'timeout :: !(Prelude.Maybe Data.Word.Word32),
-- _DtUpdateReq'sloppyQuorum :: !(Prelude.Maybe Prelude.Bool),
-- _DtUpdateReq'nVal :: !(Prelude.Maybe Data.Word.Word32),

    Key type' bucket k =
      key

    fromResponse :: Proto.UpdateCrdtResponse -> Counter
    fromResponse response =
      Counter
        { key =
            if ByteString.null k
              then key { key = response ^. L.key }
              else key
        , value = response ^. L.counter
        }