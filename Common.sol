// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IBankroll} from "./interfaces/IBankroll.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import {IVRFCoordinatorV2} from "./interfaces/IVRFCoordinatorV2.sol";
import "./interfaces/IBlast.sol";


contract Common is ReentrancyGuard {
    using SafeERC20 for IERC20;

    uint256 public VRFFees;
    address public ChainLinkVRF;
    bytes32 chainlinkVRFKeyHash;
    uint64 chainlinkVRFSubscriptionId;

    AggregatorV3Interface public LINK_ETH_FEED;
    IVRFCoordinatorV2 public IChainLinkVRF;
    IBankroll public Bankroll;

    error NotApprovedBankroll();
    error InvalidValue(uint256 required, uint256 sent);
    error TransferFailed();
    error RefundFailed();
    error NotOwner(address want, address have);
    error ZeroWager();
    error PlayerSuspended(uint256 suspensionTime);

    function setupBlast(address _blast) internal {
        IBlast(_blast).configureAutomaticYield();
    }
    
    function _transferWager(
        address tokenAddress,
        uint256 wager,
        uint256 gasAmount,
        address msgSender
    ) internal returns (uint256 VRFfee) {
        if (!Bankroll.getIsValidWager(address(this), tokenAddress)) {
            revert NotApprovedBankroll();
        }
        if (wager == 0) {
            revert ZeroWager();
        }
        
        VRFfee = getVRFFee(gasAmount);

        if (tokenAddress == address(0)) {
            if (msg.value < wager + VRFfee) {
                revert InvalidValue(wager + VRFfee, msg.value);
            }
            _refundExcessValue(msg.value - (VRFfee + wager));
        } else {
            if (msg.value < VRFfee) {
                revert InvalidValue(VRFfee, msg.value);
            }

            IERC20(tokenAddress).safeTransferFrom(
                msgSender,
                address(this),
                wager
            );

            _refundExcessValue(msg.value - VRFfee);
        }
        VRFFees += VRFfee;
    }

    function _transferToBankroll(
        address tokenAddress,
        uint256 amount
    ) internal {
        if (tokenAddress == address(0)) {
            (bool success, ) = payable(address(Bankroll)).call{value: amount}(
                ""
            );
            if (!success) {
                revert RefundFailed();
            }
        } else {
            IERC20(tokenAddress).safeTransfer(address(Bankroll), amount);
        }
    }

    function getVRFFee(uint256 gasAmount) public view returns (uint256 fee) {
        (, int256 answer, , , ) = LINK_ETH_FEED.latestRoundData();
        (uint32 fulfillmentFlatFeeLinkPPMTier1, , , , , , , , ) = IChainLinkVRF
            .getFeeConfig();

        fee =
            tx.gasprice *
            (gasAmount) +
            ((1e12 *
                uint256(fulfillmentFlatFeeLinkPPMTier1) *
                uint256(answer)) / 1e18);
    }

    function _refundExcessValue(uint256 refund) internal {
        if (refund == 0) {
            return;
        }
        (bool success, ) = payable(msg.sender).call{value: refund}("");
        if (!success) {
            revert RefundFailed();
        }
    }

    function _payVRFFee(uint256 gasAmount) internal returns (uint256 VRFfee) {
        VRFfee = getVRFFee(gasAmount);
        if (msg.value < VRFfee) {
            revert InvalidValue(VRFfee, msg.value);
        }
        _refundExcessValue(msg.value - VRFfee);
        VRFFees += VRFfee;
    }

    function transferFees() external  {
        uint256 fee = VRFFees;
        VRFFees = 0;
        (bool success, ) = payable(address(Bankroll)).call{value: fee}("");
        if (!success) {
            revert TransferFailed();
        }
    }


    function _transferPayout(
        address player,
        uint256 payout,
        address tokenAddress
    ) internal {
        Bankroll.transferPayout(player, payout, tokenAddress);
    }

    function _requestRandomWords(
        uint32 numWords
    ) internal returns (uint256 s_requestId) {
        s_requestId = IVRFCoordinatorV2(ChainLinkVRF)
            .requestRandomWords(
                chainlinkVRFKeyHash,
                chainlinkVRFSubscriptionId,
                3,
                2500000,
                numWords
            );
    }
}
