// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "../interfaces/IBlast.sol";

contract Bankroll is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    mapping(address => mapping(address => uint256)) public userBalances;
    mapping(address => uint) private lastUserUpdate;
    mapping(address => uint256) public mappedBalances;
    mapping(address => bool) public isToken;
    mapping(address => bool) public isGame;

    address[] private allowedTokens;

    address public wrappedNativeToken;

    uint32 private gasLimit = 3500;

    error invalidGame(address game);
    error invalidToken(address token);
    error invalidAmount();
    error zeroAmount();
    error zeroAddress();

    event payoutTransferFailed(
        address player,
        uint256 payout,
        address tokenAddress
    );

    constructor(
        address _initialOwner,
        address _wrappedNativeToken,
        address _blast
    ) Ownable(_initialOwner) {
        wrappedNativeToken = _wrappedNativeToken;
        IBlast(_blast).configureAutomaticYield();
    }

    function getIsValidWager(
        address _game,
        address _tokenAddress
    ) external view returns (bool) {
        return (isGame[_game] && isToken[_tokenAddress]);
    }

    function setTokenAddress(
        address _tokenAddress,
        bool _isValid
    ) external onlyOwner {
        isToken[_tokenAddress] = _isValid;
        allowedTokens.push(_tokenAddress);
    }

    function setGame(address _game, bool _state) external onlyOwner {
        isGame[_game] = _state;
    }

    function getIsGame(address _game) external view returns (bool) {
        return isGame[_game];
    }

    function getAllowedTokens() external view returns (address[] memory) {
        return allowedTokens;
    }

    function getIsTokenAllowed(
        address _tokenAddress
    ) external view returns (bool) {
        return isToken[_tokenAddress];
    }

    

    function setGasLimit(uint32 _gasLimit) external onlyOwner {
        gasLimit = _gasLimit;
    }

    function getUserActualBalance(
        address _player,
        address _tokenAddress
    ) public view returns (uint256) {
        uint _tokenBalance = _tokenAddress == address(0)
            ? address(this).balance
            : IERC20(_tokenAddress).balanceOf(address(this));
        return
            (userBalances[_player][_tokenAddress] * _tokenBalance) /
            mappedBalances[_tokenAddress];
    }

    function transferPayout(
        address _player,
        uint256 _payout,
        address _tokenAddress
    ) external {
        if (!isGame[msg.sender]) revert invalidGame(msg.sender);
        _transferAmount(_player, _tokenAddress, _payout);
    }

    function _transferAmount(
        address receiver,
        address _tokenAddress,
        uint _amount
    ) internal {
        if (_tokenAddress != address(0)) {
            IERC20(_tokenAddress).safeTransfer(receiver, _amount);
        } else {
            (bool success, ) = payable(receiver).call{
                value: _amount,
                gas: gasLimit
            }("");
            if (!success) {
                (bool _success, ) = wrappedNativeToken.call{value: _amount}(
                    abi.encodeWithSignature("deposit()")
                );
                if (_success) {
                    IERC20(wrappedNativeToken).safeTransfer(receiver, _amount);
                }
            }
            emit payoutTransferFailed(receiver, _amount, _tokenAddress);
        }
    }

    function userDeposit(
        address _tokenAddress,
        uint256 _amount
    ) external payable nonReentrant {
        if (!isToken[_tokenAddress]) revert invalidToken(_tokenAddress);
        if (_amount == 0) revert zeroAmount();

        uint _finalAmount = _amount;
        if (userBalances[msg.sender][_tokenAddress] > 0) {
            uint _currentUserBalance = userBalances[msg.sender][_tokenAddress];
            uint _actualUserBalance = getUserActualBalance(
                msg.sender,
                _tokenAddress
            );
            userBalances[msg.sender][_tokenAddress] = 0;
            mappedBalances[_tokenAddress] -= _currentUserBalance;
            _finalAmount += _actualUserBalance;
        } else {
            userBalances[msg.sender][_tokenAddress] = 0;
        }

        if (_tokenAddress != address(0)) {
            IERC20(_tokenAddress).safeTransferFrom(
                msg.sender,
                address(this),
                _amount
            );
        } else {
            if (msg.value != _amount) revert invalidAmount();
        }
        userBalances[msg.sender][_tokenAddress] += _finalAmount;
        mappedBalances[_tokenAddress] += _finalAmount;
        lastUserUpdate[msg.sender] = block.timestamp;
    }

    function userWithdraw(address _tokenAddress) external nonReentrant {
        if (userBalances[msg.sender][_tokenAddress] == 0) revert zeroAmount();
        if(lastUserUpdate[msg.sender] + 3 days < block.timestamp) {
            revert("Bankroll: userWithdraw: 3 day has not passed since last deposit");
        }

        uint _currentUserBalance = userBalances[msg.sender][_tokenAddress];
        uint _actualUserBalance = getUserActualBalance(
            msg.sender,
            _tokenAddress
        );
        userBalances[msg.sender][_tokenAddress] = 0;
        mappedBalances[_tokenAddress] -= _currentUserBalance;

        _transferAmount(msg.sender, _tokenAddress, _actualUserBalance);
    }

    receive() external payable {}
}
