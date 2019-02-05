module Riak.Index
  ( Index(..)
  , get
  , getAll
  ) where

import Riak.Internal.Client  (Client, Error(..))
import Riak.Internal.Panic   (impurePanic)
import Riak.Internal.Prelude
import Riak.Request          (Request(..))
import Riak.Response         (Response(..))

import qualified Riak.Internal.Client as Client

import qualified Riak.Proto      as Proto
import qualified Riak.Proto.Lens as L

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
get ::
     MonadIO m
  => Client
  -> Text
  -> m (Either Error (Maybe Index))
get client name = liftIO $
  fromResponse <$>
    Client.exchange
      client
      (RequestGetIndex request)
      (\case
        ResponseGetIndex response -> Just response
        _ -> Nothing)

  where
    request :: Proto.GetIndexRequest
    request =
      defMessage
        & L.name .~ encodeUtf8 name

    fromResponse ::
         Either Error Proto.GetIndexResponse
      -> Either Error (Maybe Index)
    fromResponse = \case
      -- TODO test that riak returns "notfound" here instead of an empty list
      -- Left (Error "notfound") ->
      --   Right Nothing

      Left err ->
        Left err

      Right response ->
        case response ^. L.index of
          [index] ->
            Right $ Just $ Index
              { name = name
              , schema = decodeUtf8 (index ^. L.schema)
              , n = index ^. L.maybe'n
              }

          _ ->
            impurePanic "0 or 2+ indexes"
              ( ( "request",  request  )
              , ( "response", response )
              )

-- | Get all Solr indexes.
getAll ::
     MonadIO m
  => Client
  -> m (Either Error [Index])
getAll client = liftIO $
  fromResponse <$> doGet client Nothing

  where
    fromResponse ::
         Either Error Proto.GetIndexResponse
      -> Either Error [Index]
    fromResponse = \case
      -- TODO test that riak returns "notfound" here instead of an empty list
      -- Left (Error "notfound") ->
      --   Right []
      Left err ->
        Left err

      Right response ->
        Right (map fromProto (response ^. L.index))

doGet ::
     Client
  -> Maybe Text
  -> IO (Either Error Proto.GetIndexResponse)
doGet client name =
  Client.exchange
    client
    (RequestGetIndex request)
    (\case
      ResponseGetIndex response -> Just response
      _ -> Nothing)

  where
    request :: Proto.GetIndexRequest
    request =
      defMessage
        & L.maybe'name .~ (encodeUtf8 <$> name)

fromProto :: Proto.Index -> Index
fromProto index =
  Index
    { name = decodeUtf8 (index ^. L.name)
    , schema = decodeUtf8 (index ^. L.schema)
    , n = index ^. L.maybe'n
    }
