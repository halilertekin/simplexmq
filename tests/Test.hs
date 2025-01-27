{-# LANGUAGE TypeApplications #-}

import AgentTests (agentTests)
import CoreTests.EncodingTests
import CoreTests.ProtocolErrorTests
import CoreTests.VersionRangeTests
import ServerTests
import Simplex.Messaging.Transport (TLS, Transport (..))
import Simplex.Messaging.Transport.WebSockets (WS)
import System.Directory (createDirectoryIfMissing, removeDirectoryRecursive)
import Test.Hspec

main :: IO ()
main = do
  createDirectoryIfMissing False "tests/tmp"
  hspec $ do
    describe "Core tests" $ do
      describe "Encoding tests" encodingTests
      describe "Protocol error tests" protocolErrorTests
      describe "Version range" versionRangeTests
    describe "SMP server via TLS 1.3" $ serverTests (transport @TLS)
    describe "SMP server via WebSockets" $ serverTests (transport @WS)
    describe "SMP client agent" $ agentTests (transport @TLS)
  removeDirectoryRecursive "tests/tmp"
