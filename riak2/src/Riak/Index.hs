module Riak.Index
  ( Index(..)
  , getIndex
  , getIndexes
  , putIndex
  , deleteIndex
  ) where

import Riak.Handle           (Handle)
import Riak.Internal.Prelude

import qualified Riak.Handle as Handle

import qualified Riak.Proto      as Proto
import qualified Riak.Proto.Lens as L

import Control.Lens       ((.~), (^.))
import Data.List          (head)
import Data.Text.Encoding (decodeUtf8, encodeUtf8)

-- | A Solr index.
--
-- /Note/. The index name may only contain ASCII values from @32-127@.
data Index
  = Index
  { name :: Text
  , schema :: Text
  , n :: Maybe Word32 -- TODO does riak always return this?
  }

-- | Get a Solr index.
getIndex ::
     MonadIO m
  => Handle -- ^
  -> Text -- ^
  -> m (Either Handle.Error (Maybe Index))
getIndex handle name = liftIO $
  liftIO (fromResponse <$> Handle.getIndex handle (Just (encodeUtf8 name)))

  where
    fromResponse ::
         Either Handle.Error [Proto.Index]
      -> Either Handle.Error (Maybe Index)
    fromResponse = \case
      -- TODO test that riak returns "notfound" here instead of an empty list
      -- Left "notfound" ->
      --   Right Nothing

      Left err ->
        Left err

      Right (head -> index) ->
        Right $ Just $ Index
          { name = name
          , schema = decodeUtf8 (index ^. L.schema)
          , n = index ^. L.maybe'n
          }

-- | Get all Solr indexes.
getIndexes ::
     MonadIO m
  => Handle -- ^
  -> m (Either Handle.Error [Index])
getIndexes handle =
  liftIO (fromResponse <$> Handle.getIndex handle Nothing)

  where
    fromResponse ::
         Either Handle.Error [Proto.Index]
      -> Either Handle.Error [Index]
    fromResponse = \case
      -- TODO test that riak returns "notfound" here instead of an empty list
      -- Left "notfound" ->
      --   Right []
      Left err ->
        Left err

      Right indexes ->
        Right (map fromProto indexes)

-- | Put a Solr index.
putIndex ::
     MonadIO m
  => Handle -- ^
  -> Index -- ^
  -> m (Either Handle.Error ())
putIndex handle index = liftIO $
  Handle.putIndex handle request

  where
    request :: Proto.PutIndexRequest
    request =
      Proto.defMessage
        & L.index .~ toProto index
        -- TODO put index timeout
        -- & L.maybe'timeout .~ undefined

-- | Delete a Solr index.
deleteIndex ::
     MonadIO m
  => Handle -- ^
  -> Text -- ^
  -> m (Either Handle.Error ())
deleteIndex handle name = liftIO $
  Handle.deleteIndex handle (encodeUtf8 name)

fromProto :: Proto.Index -> Index
fromProto index =
  Index
    { name = decodeUtf8 (index ^. L.name)
    , schema = decodeUtf8 (index ^. L.schema)
    , n = index ^. L.maybe'n
    }

toProto :: Index -> Proto.Index
toProto Index { name, schema, n } =
  Proto.defMessage
    & L.name .~ encodeUtf8 name
    & L.schema .~ encodeUtf8 schema
    & L.maybe'n .~ n
