{-# LANGUAGE ViewPatterns #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE DeriveDataTypeable #-}
{-# OPTIONS_GHC -Wall #-}

-- | Support dynamic typing.

module Dynamic
  ( Dynamic(..)
  -- * Accessors
  , (!)
  , set
  , modify
  -- * Input
  , fromJson
  , fromCsv
  , fromCsvNamed
  , fromJsonFile
  , fromCsvFile
  , fromCsvFileNamed
  , fromList
  , fromDict
  -- * Ouput
  , toJson
  , toCsv
  , toCsvNamed
  , toJsonFile
  , toCsvFile
  , toDouble
  , toInt
  , toBool
  , toList
  , toKeys
  , toElems
  -- * Web requests
  , get
  , getJson
  , postJson
  ) where

import           Control.Arrow ((***))
import           Control.Exception
import qualified Data.Aeson as Aeson
import qualified Data.Aeson.Encode.Pretty as Aeson
import           Data.Bifunctor
import qualified Data.ByteString.Lazy as L
import qualified Data.Csv as Csv
import           Data.Data
import           Data.HashMap.Strict (HashMap)
import qualified Data.HashMap.Strict as HM
import           Data.Maybe
import           Data.String
import           Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.Encoding as T
import qualified Data.Text.IO as T
import qualified Data.Text.Read as T
import           Data.Vector (Vector)
import qualified Data.Vector as V
import           GHC.Generics
import           Network.HTTP.Simple

-- | A dynamic error.
data DynamicException
  = DynamicTypeError Text
  | ParseError Text
  | NoSuchKey Text
  | NoSuchIndex Int
  deriving (Show, Typeable)
instance Exception DynamicException

-- | The dynamic type.
data Dynamic
  = Dictionary !(HashMap Text Dynamic)
  | Array !(Vector Dynamic)
  | String !Text
  | Double !Double
  | Bool !Bool
  | Null
  deriving (Eq, Typeable, Data, Generic, Ord)

--------------------------------------------------------------------------------
-- Class instances

-- | Dumps it to JSON.
instance Show Dynamic where
  show = T.unpack . toJson

-- | Converts everything to a double.
instance Num Dynamic where
  (toDouble -> x) + (toDouble -> y) = Double (x + y)
  (toDouble -> x) * (toDouble -> y) = Double (x * y)
  abs = Double . abs . toDouble
  signum = Double . signum . toDouble
  fromInteger = Double . fromInteger
  negate = Double . negate . toDouble

-- | Treats the dynamic as a double.
instance Enum Dynamic where
  toEnum = Double . fromIntegral
  fromEnum = fromEnum . toDouble

-- | Implemented via 'toDouble'.
instance Real Dynamic where
  toRational = toRational . toDouble

instance Fractional Dynamic where
  fromRational = Double . fromRational
  recip = Double . recip . toDouble

-- | Implemented via 'Double'.
instance Integral Dynamic where
  toInteger = toInteger . toInt
  quotRem x y =
    (Double . fromIntegral *** Double . fromIntegral)
      (quotRem (toInt x) (toInt y))

-- | Makes a 'String'.
instance IsString Dynamic where
  fromString = String . T.pack

-- | Does what you'd expect.
instance Aeson.FromJSON Dynamic where
  parseJSON =
    \case
      Aeson.Array a -> Array <$> traverse Aeson.parseJSON a
      Aeson.Number sci -> pure (Double (realToFrac sci))
      Aeson.Bool v -> pure (Bool v)
      Aeson.Null -> pure Null
      Aeson.Object hm -> fmap Dictionary (Aeson.parseJSON (Aeson.Object hm))
      Aeson.String s -> pure (String s)

-- | Pretty much a 1:1 correspondance.
instance Aeson.ToJSON Dynamic where
  toJSON =
    \case
      Dictionary v -> Aeson.toJSON v
      Array v -> Aeson.toJSON v
      String t -> Aeson.toJSON t
      Double t -> Aeson.toJSON t
      Bool t -> Aeson.toJSON t
      Null -> Aeson.toJSON Aeson.Null

-- | Produces an array representing a row of columns.
instance Csv.FromRecord Dynamic where
  parseRecord xs = Array <$> traverse Csv.parseField xs

-- | Produces a dictionary representing a row of columns.
instance Csv.FromNamedRecord Dynamic where
  parseNamedRecord xs =
    Dictionary . HM.fromList . map (first T.decodeUtf8) . HM.toList <$>
    traverse Csv.parseField xs

-- | Tries to figure out decimals, coerce true/false into 'Bool', and
-- null into 'Null'.
instance Csv.FromField Dynamic where
  parseField bs =
    case T.decimal text of
      Left {} ->
        case T.toLower (T.strip text) of
          "true" -> pure (Bool True)
          "false" -> pure (Bool False)
          "null" -> pure Null
          _ -> asString
      Right (v, _) -> pure v
    where
      text = T.decodeUtf8 bs
      asString = pure (String (T.decodeUtf8 bs))

-- | Renders the elements of containers, or else a singleton.
instance Csv.ToRecord Dynamic where
  toRecord =
    \case
      Dictionary hm -> V.map Csv.toField (V.fromList (HM.elems hm))
      Array vs -> V.map Csv.toField vs
      String s -> V.singleton (T.encodeUtf8 s)
      Double d -> V.singleton (Csv.toField d)
      Bool d -> V.singleton (Csv.toField (Bool d))
      Null -> mempty

-- | Just works on dictionaries.
instance Csv.ToNamedRecord Dynamic where
  toNamedRecord =
    \case
      Dictionary hm ->
        HM.fromList (map (bimap T.encodeUtf8 Csv.toField) (HM.toList hm))
      _ -> throw (TypeError "Can't make a CSV row out of a non-dictionary")

-- | Identity for strings, else JSON output.
instance Csv.ToField Dynamic where
  toField =
    \case
      String i -> T.encodeUtf8 i
      other -> L.toStrict (Aeson.encode other)

-- | Nulls are identity, arrays/dicts join, string + double/bool
-- append everything else is @toText x <> toText y@.
instance Semigroup Dynamic where
  Null <> x = x
  x <> Null = x
  Array xs <> Array ys = Array (xs <> ys)
  Dictionary x <> Dictionary y = Dictionary (x <> y)
  String x <> String y = String (x <> y)
  String x <> Double y = String (x <> toText (Double y))
  Double x <> String y = String (toText (Double x) <> y)
  String x <> Bool y = String (x <> toText (Bool y))
  Bool x <> String y = String (toText (Bool x) <> y)
  -- Everything else
  x <> y = String (toText x <> toText y)

--------------------------------------------------------------------------------
-- Accessors

-- | @object ! key@ to access the field at key.
(!) :: Dynamic -> Dynamic -> Dynamic
(!) obj k =
  case obj of
    Dictionary mp ->
      case HM.lookup (toText k) mp of
        Nothing -> Null
        Just v -> v
    Array v ->
      case v V.!? toInt k of
        Nothing -> Null
        Just el -> el
    String str -> String (T.take 1 (T.drop (toInt k) str))
    _ -> throw (DynamicTypeError "Can't index this type of value.")

infixl 9 !

-- | @set key value object@ -- set the field's value.
set :: Dynamic -> Dynamic -> Dynamic -> Dynamic
set k v obj =
  case obj of
    Dictionary mp -> Dictionary (HM.insert (toText k) v mp)
    _ -> throw (DynamicTypeError "Not an object!")

-- | @modify k f obj@ -- modify the value at key.
modify :: Dynamic -> (Dynamic -> Dynamic) -> Dynamic -> Dynamic
modify k f obj =
  case obj of
    Dictionary mp -> Dictionary (HM.adjust f (toText k) mp)
    _ -> throw (DynamicTypeError "Not an object!")

--------------------------------------------------------------------------------
-- Output

-- | Convert to string if string, or else JSON encoding.
toText :: Dynamic -> Text
toText =
  \case
    String s -> s
    orelse -> toJson orelse

-- | Convert a dynamic value to a Double.
toDouble :: Dynamic -> Double
toDouble =
  \case
    String t ->
      case T.double t of
        Left {} ->
          throw (DynamicTypeError ("Couldn't treat string as number: " <> t))
        Right (v, _) -> v
    Double d -> d
    Bool {} -> throw (DynamicTypeError "Can't treat bool as number.")
    Null -> 0
    Dictionary {} ->
      throw (DynamicTypeError "Can't treat dictionary as number.")
    Array {} -> throw (DynamicTypeError "Can't treat array as number.")

-- | Convert a dynamic value to an Int.
toInt :: Dynamic -> Int
toInt = floor . toDouble

-- | Produces a JSON representation of the string.
toJson :: Dynamic -> Text
toJson = T.decodeUtf8 . L.toStrict . Aeson.encodePretty

-- | Produces a JSON representation of the string.
toJsonFile :: FilePath -> Dynamic -> IO ()
toJsonFile fp = L.writeFile fp . Aeson.encodePretty

-- | Produces a JSON representation of the string.
toCsv :: [Dynamic] -> Text
toCsv = T.decodeUtf8 . L.toStrict . Csv.encode

-- | Produces a JSON representation of the string.
toCsvFile :: FilePath -> [Dynamic] -> IO ()
toCsvFile fp = L.writeFile fp . Csv.encode

-- | Produces a JSON representation of the string.
toCsvNamed :: [Dynamic] -> Text
toCsvNamed xs = rows xs
  where
    rows = T.decodeUtf8 . L.toStrict . Csv.encodeByName (makeHeader xs)
    makeHeader rs =
      case rs of
        (Dictionary hds:_) -> V.fromList (map T.encodeUtf8 (HM.keys hds))
        _ -> mempty

-- | Convert to a boolean.
toBool :: Dynamic -> Bool
toBool =
  \case
    Dictionary m -> not (HM.null m)
    Array v -> not (V.null v)
    Bool b -> b
    Double 0 -> False
    Double {} -> True
    Null -> False
    String text ->
      case T.toLower (T.strip text) of
        "true" -> True
        "false" -> False
        _ -> not (T.null text)

-- | Convert to a list.
toList :: Dynamic -> [Dynamic]
toList =
  \case
    Array v -> V.toList v
    Dictionary kvs ->
      map
        (\(k, v) -> Dictionary (HM.fromList [("key", String k), ("value", v)]))
        (HM.toList kvs)
    rest -> [rest]

-- | Get all the keys.
toKeys :: Dynamic -> [Dynamic]
toKeys =
  \case
    Array v -> V.toList v
    Dictionary kvs -> map String (HM.keys kvs)
    rest -> [rest]

-- | Get all the elems.
toElems :: Dynamic -> [Dynamic]
toElems =
  \case
    Array v -> V.toList v
    Dictionary kvs -> HM.elems kvs
    rest -> [rest]

--------------------------------------------------------------------------------
-- Input

-- | Read JSON into a Dynamic.
fromJson :: Text -> Dynamic
fromJson =
  fromMaybe (throw (ParseError "Unable to parse JSON.")) .
  Aeson.decode . L.fromStrict . T.encodeUtf8

-- | Read CSV into a list of rows with columns (don't use column names).
fromCsv :: Text -> [[Dynamic]]
fromCsv =
  V.toList .
  either (const (throw (ParseError "Unable to parse CSV."))) id .
  Csv.decode Csv.NoHeader . L.fromStrict . T.encodeUtf8

-- | Read CSV into a list of rows (use column names).
fromCsvNamed :: Text -> [Dynamic]
fromCsvNamed =
  V.toList .
  either (const (throw (ParseError "Unable to parse CSV."))) snd .
  Csv.decodeByName . L.fromStrict . T.encodeUtf8

-- | Same as 'fromJson' but from a file.
fromJsonFile :: FilePath -> IO Dynamic
fromJsonFile = fmap fromJson . T.readFile

-- | Same as 'fromCsv' but from a file.
fromCsvFile :: FilePath -> IO [[Dynamic]]
fromCsvFile = fmap fromCsv . T.readFile

-- | Same as 'fromCsvFileNamed' but from a file.
fromCsvFileNamed :: FilePath -> IO [Dynamic]
fromCsvFileNamed = fmap fromCsvNamed . T.readFile

-- | Convert a list of dynamics to a dynamic list.
fromList :: [Dynamic] -> Dynamic
fromList = Array . V.fromList

-- | Convert a list of key/pairs to a dynamic dictionary.
fromDict :: [(Dynamic, Dynamic)] -> Dynamic
fromDict hm = Dictionary (HM.fromList (map (bimap toText id) hm))

--------------------------------------------------------------------------------
-- Web helpers

-- | HTTP request for text content.
get :: Dynamic -> IO Text
get url = do
  response <-
    httpBS
      (addRequestHeader
         "User-Agent"
         "haskell-dynamic"
         (fromString (T.unpack (toText url))))
  pure (T.decodeUtf8 (getResponseBody response))

-- | HTTP request for text content.
getJson :: Dynamic -> IO Dynamic
getJson = fmap fromJson . get

-- | HTTP request for text content.
postJson :: Dynamic -> Dynamic -> IO Text
postJson url body = do
  response <-
    httpBS
      (addRequestHeader
         "User-Agent"
         "haskell-dynamic"
         (setRequestMethod
            "POST"
            (setRequestBodyJSON body (fromString (T.unpack (toText url))))))
  pure (T.decodeUtf8 (getResponseBody response))
