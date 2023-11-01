pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import "../src/interfaces/IBPLockManager.sol";
import "../src/interfaces/IJB721StakingDelegate.sol";
import "../src/interfaces/IJBTiered721MinimalDelegate.sol";
import "../src/interfaces/IJBTiered721MinimalDelegateStore.sol";

contract InterfaceTest is Test {
  function testLogInterfaceId() public view {
    console.logString("IBPLockManager:");
    console.logBytes4(type(IBPLockManager).interfaceId);
    console.logString("IJB721StakingDelegate:");
    console.logBytes4(type(IJB721StakingDelegate).interfaceId);
    console.logString("IJBTiered721MinimalDelegate:");
    console.logBytes4(type(IJBTiered721MinimalDelegate).interfaceId);
    console.logString("IJBTiered721MinimalDelegateStore:");
    console.logBytes4(type(IJBTiered721MinimalDelegateStore).interfaceId);
  }
}
