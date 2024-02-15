// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IBankroll {
    function userBalances(address, address) external view returns (uint256);

    function mappedBalances(address) external view returns (uint256);

    function isToken(address) external view returns (bool);

    function isGame(address) external view returns (bool);

    function allowedTokens(uint256) external view returns (address);

    function wrappedNativeToken() external view returns (address);

    function gasLimit() external view returns (uint32);

    function getIsValidWager(address, address) external view returns (bool);

    function setTokenAddress(address, bool) external;

    function setGame(address, bool) external;

    function getIsGame(address) external view returns (bool);

    function getAllowedTokens() external view returns (address[] memory);

    function getIsTokenAllowed(address) external view returns (bool);

    function setGasLimit(uint32) external;

    function getUserActualBalance(
        address,
        address
    ) external view returns (uint256);

    function transferPayout(
        address,
        uint256,
        address
    ) external;

}
