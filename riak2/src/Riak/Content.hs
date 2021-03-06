module Riak.Content
  ( Content(..)
  , newContent
  ) where

import Riak.Internal.Prelude
import Riak.Internal.SecondaryIndex (SecondaryIndex)

import Data.Time          (UTCTime(..))
import Data.Time.Calendar (Day(..))


-- | Object content.
data Content a
  = Content
  { charset :: !(Maybe ByteString) -- ^ Charset
  , encoding :: !(Maybe ByteString) -- ^ Content encoding
  , indexes :: ![SecondaryIndex] -- ^ Secondary indexes
  , lastModified :: !UTCTime -- ^ Last modified.
  , metadata :: ![(ByteString, Maybe ByteString)] -- ^ User metadata
  , type' :: !(Maybe ByteString) -- ^ Content type
  , ttl :: !(Maybe Word32) -- ^ Time to live. Unused on write. TODO NominalDiffTime
  , value :: !a -- ^ Value
  } deriving stock (Eq, Functor, Generic, Show)

-- | Create a new content from a value.
--
-- An arbitrary date in the 1850s is chosen for @lastModified@. This is only
-- relevant if you are using the unrecommended bucket settings that both
-- disallow siblings and use internal (unreliable) timestamps for conflict
-- resolution.
newContent ::
     a -- ^ Value
  -> Content a
newContent value =
  Content
    { charset = Nothing
    , encoding = Nothing
    , indexes = []
    , lastModified = UTCTime (ModifiedJulianDay 0) 0
    , metadata = []
    , ttl = Nothing
    , type' = Nothing
    , value = value
    }
