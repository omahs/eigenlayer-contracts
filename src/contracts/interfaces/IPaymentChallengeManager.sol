// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

interface IPaymentChallengeManager {

    function resolvePaymentChallenge(address, bool) external;

    function paymentFraudProofInterval() external returns (uint256);

    function paymentFraudProofCollateral() external returns (uint256);

    function getPaymentCollateral(address) external returns (uint256);
}