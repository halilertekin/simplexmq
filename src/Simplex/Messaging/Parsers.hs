{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE OverloadedStrings #-}

module Simplex.Messaging.Parsers where

import Control.Monad.Trans.Except
import Data.Attoparsec.ByteString.Char8 (Parser)
import qualified Data.Attoparsec.ByteString.Char8 as A
import Data.Bifunctor (first)
import Data.ByteString.Base64
import Data.ByteString.Char8 (ByteString)
import qualified Data.ByteString.Char8 as B
import Data.Char (isAlphaNum)
import Data.Time.Clock (UTCTime)
import Data.Time.ISO8601 (parseISO8601)
import Data.Typeable (Typeable)
import Database.SQLite.Simple (ResultError (..), SQLData (..))
import Database.SQLite.Simple.FromField (FieldParser, returnError)
import Database.SQLite.Simple.Internal (Field (..))
import Database.SQLite.Simple.Ok (Ok (Ok))
import Simplex.Messaging.Util ((<$?>))
import Text.Read (readMaybe)

base64P :: Parser ByteString
base64P = decode <$?> paddedBase64 rawBase64P

paddedBase64 :: Parser ByteString -> Parser ByteString
paddedBase64 raw = (<>) <$> raw <*> pad
  where
    pad = A.takeWhile (== '=')

rawBase64P :: Parser ByteString
rawBase64P = A.takeWhile1 (\c -> isAlphaNum c || c == '+' || c == '/')

-- rawBase64UriP :: Parser ByteString
-- rawBase64UriP = A.takeWhile1 (\c -> isAlphaNum c || c == '-' || c == '_')

tsISO8601P :: Parser UTCTime
tsISO8601P = maybe (fail "timestamp") pure . parseISO8601 . B.unpack =<< A.takeTill wordEnd

parse :: Parser a -> e -> (ByteString -> Either e a)
parse parser err = first (const err) . parseAll parser

parseAll :: Parser a -> (ByteString -> Either String a)
parseAll parser = A.parseOnly (parser <* A.endOfInput)

parseE :: (String -> e) -> Parser a -> (ByteString -> ExceptT e IO a)
parseE err parser = except . first err . parseAll parser

parseE' :: (String -> e) -> Parser a -> (ByteString -> ExceptT e IO a)
parseE' err parser = except . first err . A.parseOnly parser

parseRead :: Read a => Parser ByteString -> Parser a
parseRead = (>>= maybe (fail "cannot read") pure . readMaybe . B.unpack)

parseRead1 :: Read a => Parser a
parseRead1 = parseRead $ A.takeTill wordEnd

parseRead2 :: Read a => Parser a
parseRead2 = parseRead $ do
  w1 <- A.takeTill wordEnd <* A.char ' '
  w2 <- A.takeTill wordEnd
  pure $ w1 <> " " <> w2

wordEnd :: Char -> Bool
wordEnd c = c == ' ' || c == '\n'

parseString :: (ByteString -> Either String a) -> (String -> a)
parseString p = either error id . p . B.pack

blobFieldParser :: Typeable k => Parser k -> FieldParser k
blobFieldParser = blobFieldDecoder . parseAll

blobFieldDecoder :: Typeable k => (ByteString -> Either String k) -> FieldParser k
blobFieldDecoder dec = \case
  f@(Field (SQLBlob b) _) ->
    case dec b of
      Right k -> Ok k
      Left e -> returnError ConversionFailed f ("couldn't parse field: " ++ e)
  f -> returnError ConversionFailed f "expecting SQLBlob column type"
