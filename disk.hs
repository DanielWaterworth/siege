-- Experimental Disk based backend
-- Append only to begin with, at some point I'll make it do log structuring

import Prelude hiding (null)
import Nullable

import Control.Concurrent
import Control.Monad
import Control.Monad.Trans.Error
import StringHelper
import System.IO
import Flushable
import NetworkProtocol
import NetworkHelper

import Store

import DBNode
import DBNodeBinary

import Data.Int
import Data.Binary as Bin
import qualified Data.ByteString as B

import System.IO

import StringHelper

newtype DiskRef = DiskRef Word64 deriving (Eq, Show)

instance Binary DiskRef where
  get = liftM DiskRef Bin.get
  put (DiskRef r) = Bin.put r

instance Nullable DiskRef where
  empty = DiskRef (-1)
  null = (== empty)

getNode :: Handle -> DiskRef -> IO (Node DiskRef)
getNode hnd (DiskRef r) = do
  hSeek hnd AbsoluteSeek $ fromIntegral r
  sz <- B.hGet hnd 8
  v <- B.hGet hnd $ fromIntegral (decode (bToL sz) :: Word64)
  return $ decode $ bToL v

putNode :: Handle -> Node DiskRef -> IO DiskRef
putNode hnd node = do
  hSeek hnd SeekFromEnd 0
  pos <- hTell hnd
  let n' = lToB $ encode node
  let sz = B.length n'
  B.hPut hnd $ lToB $ encode sz
  B.hPut hnd n'
  return $ DiskRef $ fromIntegral pos

withHandle :: Handle -> StoreT DiskRef (Node DiskRef) IO a -> IO a
withHandle hnd op = do
  v <- runStoreT op
  case v of
    Done a -> return a
    Get k c -> do
      node <- getNode hnd k
      withHandle hnd $ c node
    Store v c -> do
      ref <- putNode hnd v
      withHandle hnd $ c ref

main = do
  withFile "./test.db" ReadWriteMode (\hnd -> do
    var <- newFVar empty
    forkIO $ forever $ flushFVar (\head -> do
      print ("new head", head)
      -- TODO write reference to disk somehow
      return ()) var
    listenAt 4050 (\sock -> do
      print "new socket [="
      convert protocol sock var (withHandle hnd)))
