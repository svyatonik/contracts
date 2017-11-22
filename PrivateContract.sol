//! BasicCoin ECR20-compliant token contract
//! By Parity Team, 2017.

pragma solidity ^0.4.17;

contract Private {
    address[] validators;
    bytes state;
    bytes code;
    
    function getValidators() public constant returns (address[]) {
        return validators;
    }
    
    function getCode() public constant returns (bytes) {
        return code;
    }
    
    function getState() public constant returns (bytes) {
        return state;
    }
    
    function setState(bytes ns, uint8[] v, bytes32[] r, bytes32[]s) public {
        var state_hash = keccak256(ns);
        for (uint i = 0; i < validators.length; i++) {
            if (ecrecover(state_hash, v[i], r[i], s[i]) != validators[i])
                revert();
        }
        state = ns;
    }
    
    function Private(address[] v, bytes c, bytes s) public {
        validators = v;
        code = c;
        state = s;
    }
}