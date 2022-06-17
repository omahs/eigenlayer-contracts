// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;
import "./IDataLayr.sol";


interface IDataLayrForcedDisclosureManager {

    function resolveDisclosureChallenge(bytes32, address, bool) external;

    function disclosureFraudProofInterval() external returns (uint256);


    /**
     @notice A merkle tree of powers of srs (represented by s) is constructed off-chain:

                                                    TauMerkleRoot
                                                        :    
                                                        :    
                         ____________ ....                             .... ____________              
                        |                                                               |
                        |                                                               |    
              __h(h(s^0)||h(s^1))___                                        __h(h(s^{d-2})||h(s^{d-1}))___  
             |                      |                                      |                              |   
             |                      |                                      |                              |
           h(s^0)                 h(s^1)                               h(s^{d-2})                   h(s^{d-1}) 
     
     Only TauMerkleRoot is stored on-chain. Note that d = 2^32.
     This function returns powersOfTauMerkleRoot.
     */
    function powersOfTauMerkleRoot() external returns(bytes32);



    function numPowersOfTau() external returns(uint48);
    function log2NumPowersOfTau() external returns(uint48);
    
    function getPolyHash(address, bytes32) external returns(bytes32);

    function dataLayr() external view returns(IDataLayr);
}