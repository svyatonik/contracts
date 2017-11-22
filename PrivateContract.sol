//! BasicCoin ECR20-compliant token contract
//! By Parity Team, 2017.

pragma solidity 0.4.18;


contract Private {
    address[] public validators;
    bytes public state;
    bytes public code;
    uint256 public nonce;

    function Private(address[] initialValidators, bytes initialCode, bytes initialState) public {
        validators = initialValidators;
        code = initialCode;
        state = initialState;
        nonce = 1;
    }
    
    function getValidators() public constant returns (address[]) {
        return validators;
    }
    
    function getCode() public constant returns (bytes) {
        return code;
    }
    
    function getState() public constant returns (bytes) {
        return state;
    }
    
    function setState(bytes newState, uint8[] v, bytes32[] r, bytes32[] s) public {
        var noncedStateHash = keccak256([keccak256(newState), bytes32(nonce)]);
        for (uint i = 0; i < validators.length; i++) {
            if (ecrecover(noncedStateHash, v[i], r[i], s[i]) != validators[i])
                revert();
        }
        state = newState;
        nonce = nonce + 1;
    }
}