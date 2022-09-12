// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9.0;

import "../interfaces/IPauserRegistry.sol";


contract PauserRegistry is IPauserRegistry {

    address public pauser;
    address public unpauser;

    event PauserSet (
        address newPauser
    );

    event UnpauserSet (
        address newUnpauser
    );

    modifier onlyPauser {
        require(msg.sender == pauser,  "msg.sender is not permissioned as pauser");
        _;
    }

    modifier onlyUnpauser {
        require(msg.sender == unpauser, "msg.sender is not permissioned as unpauser");
        _;
    }

    constructor(
        address _pauser,
        address _unpauser
    ) {
        pauser = _pauser;
        unpauser = _unpauser;


        emit PauserSet(pauser);
        emit UnpauserSet(unpauser);
        
    }

    //sets new pauser - only callable by unpauser, as the unpauser has a higher threshold
    function setPauser(address newPauser) external onlyUnpauser {
        require(pauser != address(0), "pauser has not been inititalized by registry");
        pauser = newPauser;

        emit PauserSet(newPauser);
    }

    function setUnpauser(address newUnpauser) external onlyUnpauser {
        require(unpauser != address(0), "unpauser has not been inititalized by registry");
        unpauser = newUnpauser;

        emit UnpauserSet(newUnpauser);
    }
}