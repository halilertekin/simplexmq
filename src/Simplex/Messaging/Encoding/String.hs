{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE OverloadedStrings #-}

module Simplex.Messaging.Encoding.String
  ( StrEncoding (..),
    Str (..),
    strP_,
    strToJSON,
    strToJEncoding,
    strParseJSON,
    base64urlP,
  )
where

import Control.Applicative (optional)
import Data.Aeson (FromJSON (..), ToJSON (..))
import qualified Data.Aeson as J
import qualified Data.Aeson.Encoding as JE
import qualified Data.Aeson.Types as JT
import Data.Attoparsec.ByteString.Char8 (Parser)
import qualified Data.Attoparsec.ByteString.Char8 as A
import qualified Data.ByteString.Base64.URL as U
import Data.ByteString.Char8 (ByteString)
import qualified Data.ByteString.Char8 as B
import Data.Char (isAlphaNum)
import qualified Data.List.NonEmpty as L
import Data.Text.Encoding (decodeLatin1, encodeUtf8)
import Data.Word (Word16)
import Simplex.Messaging.Parsers (parseAll)
import Simplex.Messaging.Util ((<$?>))

-- | Serializing human-readable and (where possible) URI-friendly strings for SMP and SMP agent protocols
class StrEncoding a where
  {-# MINIMAL strEncode, (strDecode | strP) #-}
  strEncode :: a -> ByteString

  -- Please note - if you only specify strDecode, it will use base64urlP as default parser before decoding the string
  strDecode :: ByteString -> Either String a
  strDecode = parseAll strP
  strP :: Parser a
  strP = strDecode <$?> base64urlP

-- base64url encoding/decoding of ByteStrings - the parser only allows non-empty strings
instance StrEncoding ByteString where
  strEncode = U.encode
  strDecode = U.decode
  strP = base64urlP

base64urlP :: Parser ByteString
base64urlP = do
  str <- A.takeWhile1 (\c -> isAlphaNum c || c == '-' || c == '_')
  pad <- A.takeWhile (== '=')
  either fail pure $ U.decode (str <> pad)

newtype Str = Str {unStr :: ByteString}
  deriving (Eq, Show)

instance StrEncoding Str where
  strEncode = unStr
  strP = Str <$> A.takeTill (== ' ') <* optional A.space

instance ToJSON Str where
  toJSON (Str s) = strToJSON s
  toEncoding (Str s) = strToJEncoding s

instance FromJSON Str where
  parseJSON = fmap Str . strParseJSON "Str"

instance StrEncoding a => StrEncoding (Maybe a) where
  strEncode = maybe "" strEncode
  strP = optional strP

instance StrEncoding Word16 where
  strEncode = B.pack . show
  strP = A.decimal

-- lists encode/parse as comma-separated strings
instance StrEncoding a => StrEncoding [a] where
  strEncode = B.intercalate "," . map strEncode
  strP = listItem `A.sepBy'` A.char ','

instance StrEncoding a => StrEncoding (L.NonEmpty a) where
  strEncode = strEncode . L.toList

  -- relies on sepBy1 never returning an empty list
  strP = L.fromList <$> listItem `A.sepBy1'` A.char ','

listItem :: StrEncoding a => Parser a
listItem = parseAll strP <$?> A.takeTill (== ',')

instance (StrEncoding a, StrEncoding b) => StrEncoding (a, b) where
  strEncode (a, b) = B.unwords [strEncode a, strEncode b]
  strP = (,) <$> strP_ <*> strP

instance (StrEncoding a, StrEncoding b, StrEncoding c) => StrEncoding (a, b, c) where
  strEncode (a, b, c) = B.unwords [strEncode a, strEncode b, strEncode c]
  strP = (,,) <$> strP_ <*> strP_ <*> strP

instance (StrEncoding a, StrEncoding b, StrEncoding c, StrEncoding d) => StrEncoding (a, b, c, d) where
  strEncode (a, b, c, d) = B.unwords [strEncode a, strEncode b, strEncode c, strEncode d]
  strP = (,,,) <$> strP_ <*> strP_ <*> strP_ <*> strP

instance (StrEncoding a, StrEncoding b, StrEncoding c, StrEncoding d, StrEncoding e) => StrEncoding (a, b, c, d, e) where
  strEncode (a, b, c, d, e) = B.unwords [strEncode a, strEncode b, strEncode c, strEncode d, strEncode e]
  strP = (,,,,) <$> strP_ <*> strP_ <*> strP_ <*> strP_ <*> strP

strP_ :: StrEncoding a => Parser a
strP_ = strP <* A.space

strToJSON :: StrEncoding a => a -> J.Value
strToJSON = J.String . decodeLatin1 . strEncode

strToJEncoding :: StrEncoding a => a -> J.Encoding
strToJEncoding = JE.text . decodeLatin1 . strEncode

strParseJSON :: StrEncoding a => String -> J.Value -> JT.Parser a
strParseJSON name = J.withText name $ either fail pure . parseAll strP . encodeUtf8
