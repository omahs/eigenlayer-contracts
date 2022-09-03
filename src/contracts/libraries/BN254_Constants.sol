// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

library BN254_Constants {
// modulus for the underlying field F_q of the elliptic curve
uint256 constant MODULUS =
    21888242871839275222246405745257275088696311157297823662689037894645226208583;

// negation of the generator of group G2
/**
 @dev Generator point lies in F_q2 is of the form: (x0 + ix1, y0 + iy1).
 */
uint256 constant nG2x1 =
    11559732032986387107991004021392285783925812861821192530917403151452391805634;
uint256 constant nG2x0 =
    10857046999023057135944570762232829481370756359578518086990519993285655852781;
uint256 constant nG2y1 =
    17805874995975841540914202342111839520379459829704422454583296818431106115052;
uint256 constant nG2y0 =
    13392588948715843804641432497768002650278120570034223513918757245338268106653;

// generator of group G2
/**
 @dev Generator point lies in F_q2 is of the form: (x0 + ix1, y0 + iy1).
 */
uint256 constant G2x1 =
    11559732032986387107991004021392285783925812861821192530917403151452391805634;
uint256 constant G2x0 =
    10857046999023057135944570762232829481370756359578518086990519993285655852781;
uint256 constant G2y1 =
    4082367875863433681332203403145435568316851327593401208105741076214120093531;
uint256 constant G2y0 =
    8495653923123431417604973247489272438418190587263600148770280649306958101930;

bytes32 constant powersOfTauMerkleRoot =
    0x22c998e49752bbb1918ba87d6d59dd0e83620a311ba91dd4b2cc84990b31b56f;
}