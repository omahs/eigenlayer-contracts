// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.12;

interface IEigenPodPaymentEscrow {
    // struct used to pack data into a single storage slot
    struct Payment {
        uint224 amount;
        uint32 blockCreated;
    }

    // struct used to store a single users payment data
    struct UserPayments {
        uint256 paymentsCompleted;
        Payment[] payments;
    }

    /// @notice Creates an escrowed payment for `msg.value` to the `recipient`.
    function createPayment(address recipient) external payable;

    /**
     * @notice Called in order to withdraw escrowed payments made to the caller that have passed the `withdrawalDelayBlocks` period.
     * @param maxClaimsToMake Used to limit the maximum number of payments to loop through claiming.
     */
    function claimPayments(uint256 maxClaimsToMake) external;

    /// @notice Owner-only function for modifying the value of the `withdrawalDelayBlocks` variable.
    function setWithdrawalDelayBlocks(uint256 newValue) external;

    /// @notice Getter function for the mapping `_userPayments`
    function userPayments(address user) external view returns (UserPayments memory);

    /// @notice Getter function for fetching the payment at the `index`th entry from the `_userPayments[user].payments` array
    function userPaymentByIndex(address user, uint256 index) external view returns (Payment memory);

    /// @notice Convenience function for checking whethere or not the payment at the `index`th entry from the `_userPayments[user].payments` array is currently claimable
    function canClaimPayment(address user, uint256 index) external view returns (bool);
}