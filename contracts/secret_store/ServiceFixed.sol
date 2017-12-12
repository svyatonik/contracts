//! The Secret Store service contract. Version for networks with static KeyServers set.
//!
//! Copyright 2017 Svyatoslav Nikolsky, Parity Technologies Ltd.
//!
//! Licensed under the Apache License, Version 2.0 (the "License");
//! you may not use this file except in compliance with the License.
//! You may obtain a copy of the License at
//!
//!     http://www.apache.org/licenses/LICENSE-2.0
//!
//! Unless required by applicable law or agreed to in writing, software
//! distributed under the License is distributed on an "AS IS" BASIS,
//! WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//! See the License for the specific language governing permissions and
//! limitations under the License.

pragma solidity ^0.4.18;


/// Authorities-owned contract.
contract AuthoritiesOwned {
    /// Only pass when called by authority.
    modifier onlyAuthority {
        require (isAuthority(msg.sender));
        _;
    }

    /// Only pass when sender have non-zero balance.
    modifier onlyWithBalance {
        require (balances[msg.sender] > 0);
        _;
    }

    /// Only when non-zero fee is proposed.
    modifier whenNonZeroFeeIsProposed(uint newFee) {
        require (newFee != 0);
        _;
    }

    /// Only when _new_ fee is proposed.
    modifier whenNewFeeIsProposed(uint actualFee, uint newFee) {
        require (actualFee != newFee);
        _;
    }

    /// Only when _new_ vote is proposed.
    modifier whenNewVoteIsProposed(FeeVotes storage votes, uint newFee) {
        require (votes.votes[msg.sender] != newFee);
        _;
    }

    /// Confirmations from authorities.
    struct Confirmations {
        uint threshold;
        mapping (address => bytes32) confirmations;
        address[] confirmedAuthorities;
    }

    /// Fee votes from authorities.
    struct FeeVotes {
        mapping (address => uint) votes;
    }

    /// When balance of authority is deposited by given value (in wei).
    event Deposit(address indexed authority, uint value);

    /// Constructor.
    function AuthoritiesOwned(address[] initialAuthorities) internal {
        authorities = initialAuthorities;
    }

    /// Drain balance of sender authority.
    function drain() public onlyAuthority onlyWithBalance {
        var balance = balances[msg.sender];
        balances[msg.sender] = 0;
        msg.sender.transfer(balance);
    }

    /// Pay equal amount of fee to each of authorities.
    function deposit(uint amount) internal {
        var authorityShare = amount / authorities.length;
        for (uint i = 0; i < authorities.length - 1; i++) {
            var authority = authorities[i];
            balances[authority] += authorityShare;
            Deposit(authority, authorityShare);

            amount = amount - authorityShare;
        }

        var lastAuthority = authorities[authorities.length - 1];
        balances[lastAuthority] += amount;
        Deposit(lastAuthority, amount);
    }

    /// Is authority?
    function isAuthority(address authority) internal view returns (bool) {
        var authorities = getValidatorsInternal();
        for (uint i = 0; i < authorities.length; i++) {
            if (authority == authorities[i]) {
                return true;
            }
        }
        return false;
    }

    /// Get validators list.
    function getValidatorsInternal() view internal returns (address[]) {
        return authorities;
    }

    /// Get validators count.
    function getValidatorsCountInternal() view internal returns (uint) {
        return authorities.length;
    }

    /// Check if fee voting has finished.
    function checkFeeVoting(FeeVotes storage votes, uint lastVote) view internal returns (bool) {
        uint confirmations = 0;
        var threshold = authorities.length / 2 + 1;
        for (uint i = 0; i < authorities.length; ++i) {
            if (votes.votes[authorities[i]] == lastVote) {
                confirmations += 1;
                if (confirmations >= threshold) {
                    // majority of authorities have voted for new fee
                    return true;
                }
            }
        }

        // no majority agreement
        return false;
    }

    /// Recover authority address from signature.
    function recoverAuthority(bytes32 hash, uint8 v, bytes32 r, bytes32 s) view internal returns (address) {
        var authority = ecrecover(hash, v, r, s);
        require(isAuthority(authority));
        return authority;
    }

    /// Check that we have enough confirmations from authorities.
    function insertConfirmation(Confirmations storage confirmations, address authority, bytes32 confirmation) internal returns (bool) {
        // check if haven't confirmed before
        if (confirmations.confirmations[authority] != bytes32(0)) {
            return false;
        }
        confirmations.confirmations[authority] = confirmation;
        confirmations.confirmedAuthorities.push(authority);

        // calculate number of nodes that have reported the same confirmation
        uint confirmationsCount = 1;
        if (confirmationsCount < confirmations.threshold + 1) {
            // skip last (new) authority, because we have already counted it in confirmationsCount
            for (uint i = 0; i < confirmations.confirmedAuthorities.length - 1; ++i) {
                if (confirmations.confirmations[confirmations.confirmedAuthorities[i]] == confirmation) {
                    confirmationsCount = confirmationsCount + 1;
                }
            }
        }

        return confirmationsCount >= confirmations.threshold + 1;
    }

    /// Clear internal confirmations mappings.
    function clearConfirmations(Confirmations storage confirmations) internal {
        for (uint i = 0; i < confirmations.confirmedAuthorities.length; ++i) {
            delete confirmations.confirmations[confirmations.confirmedAuthorities[i]];
        }
    }

    /// Authorities.
    address[] authorities;
    /// Balances of authorities.
    mapping (address => uint) public balances;
}


/// Server key generation contract. This contract allows to generate SecretStore KeyPairs, which
/// could be used later to sign messages.
contract ServerKeyGenerator is AuthoritiesOwned {
    /// Only pass when fee is paid.
    modifier whenServerKeyGenerationFeePaid {
        require (msg.value >= serverKeyGenerationFee);
        _;
    }

    /// Only pass when 'correct' public is passed.
    modifier validPublicKey(bytes publicKey) {
        require (publicKey.length == 64);
        _;
    }

    /// Generation request.
    struct ServerKeyGenerationRequest {
        bool isActive;
        Confirmations confirmations;
    }

    /// When new sever key generation fee value is proposed.
    event ServerKeyGenerationFeeVote(address indexed author, uint fee);
    /// When sever key generation fee is changed to new value.
    event ServerKeyGenerationFeeChanged(uint fee);
    /// When sever key generation request is received.
    event ServerKeyRequested(bytes32 indexed serverKeyId, uint indexed threshold);
    /// When server key is generated.
    event ServerKeyGenerated(bytes32 indexed serverKeyId, bytes serverKeyPublic);

    /// Vote for server generation fee change proposal.
    function voteServerKeyGenerationFee(uint fee) public onlyAuthority
        whenNonZeroFeeIsProposed(fee)
        whenNewFeeIsProposed(serverKeyGenerationFee, fee)
        whenNewVoteIsProposed(serverKeyGenerationFeeVotes, fee)
    {
        // update vote
        serverKeyGenerationFeeVotes.votes[msg.sender] = fee;
        ServerKeyGenerationFeeVote(msg.sender, fee);

        // check if there's majority agreement
        if (!checkFeeVoting(serverKeyGenerationFeeVotes, fee)) {
            return;
        }

        // ...and change actual fee
        serverKeyGenerationFee = fee;
        ServerKeyGenerationFeeChanged(fee);
    }

    /// Request new server key generation.
    /// requester_public must be unique public key (only one key can be generated for given public).
    /// Generated key will be published via ServerKeyGenerated event when available.
    function generateServerKey(bytes32 serverKeyId, uint threshold) public payable whenServerKeyGenerationFeePaid {
        var request = serverKeyGenerationRequests[serverKeyId];
        require(!request.isActive);
        require(threshold + 1 <= getValidatorsCountInternal());
        deposit(msg.value);
        request.isActive = true;
        request.confirmations.threshold = threshold;
        serverKeyGenerationRequestsKeys.push(serverKeyId);
        ServerKeyRequested(serverKeyId, threshold);
    }

    /// Called when generation is reported by one of key authorities.
    function serverKeyGenerated(
        bytes32 serverKeyId,
        bytes serverKeyPublic,
        uint8 v,
        bytes32 r,
        bytes32 s) public validPublicKey(serverKeyPublic)
    {
        // check if request still active
        var request = serverKeyGenerationRequests[serverKeyId];
        if (!request.isActive) {
            return;
        }

        // insert confirmation && check if there are enough confirmations
        var authority = recoverAuthority(keccak256(serverKeyPublic), v, r, s);
        if (!insertConfirmation(request.confirmations, authority, keccak256(serverKeyPublic))) {
            return;
        }

        // clear confirmations
        clearConfirmations(request.confirmations);
        delete serverKeyGenerationRequests[serverKeyId];
        for (uint i = 0; i < serverKeyGenerationRequestsKeys.length; ++i) {
            if (serverKeyGenerationRequestsKeys[i] == serverKeyId) {
                for (uint j = i + 1; j < serverKeyGenerationRequestsKeys.length; ++j) {
                    serverKeyGenerationRequestsKeys[j - 1] = serverKeyGenerationRequestsKeys[j];
                }
                delete serverKeyGenerationRequestsKeys[serverKeyGenerationRequestsKeys.length - 1];
                serverKeyGenerationRequestsKeys.length = serverKeyGenerationRequestsKeys.length - 1;
                break;
            }
        }

        // ...and finally fire event
        ServerKeyGenerated(serverKeyId, serverKeyPublic);
    }

    /// Get count of pending server key generation requests.
    function serverKeyGenerationRequestsCount() view public returns (uint) {
        return serverKeyGenerationRequestsKeys.length;
    }

    /// Get server key id request with given index.
    function getServerKeyId(uint index) view public returns (bytes32) {
        require(index < serverKeyGenerationRequestsKeys.length);
        var request = serverKeyGenerationRequests[serverKeyGenerationRequestsKeys[index]];
        require(request.isActive);
        return serverKeyGenerationRequestsKeys[index];
    }

    /// Get server key generation request with given index.
    function getServerKeyThreshold(bytes32 serverKeyId) view public returns (uint) {
        var request = serverKeyGenerationRequests[serverKeyId];
        require(request.isActive);
        return request.confirmations.threshold;
    }

    /// Get server key confirmation status (true - confirmed by address, false otherwise).
    function getServerKeyConfirmationStatus(bytes32 serverKeyId, address authority) view public returns (bool) {
        var request = serverKeyGenerationRequests[serverKeyId];
        require(request.isActive);
        return request.confirmations.confirmations[authority] != bytes32(0);
    }

    /// Server key generation fee. TODO: change to actual value
    uint public serverKeyGenerationFee = 1 finney;
    /// Mapping of authority => fee it supports. When some fee gets majority of votes,
    /// it becames actual fee.
    FeeVotes serverKeyGenerationFeeVotes;

    /// Pending generation requests.
    mapping (bytes32 => ServerKeyGenerationRequest) serverKeyGenerationRequests;
    /// Pending requests keys.
    bytes32[] serverKeyGenerationRequestsKeys;
}


/// Secret store service contract.
contract SecretStoreService is AuthoritiesOwned, ServerKeyGenerator {
    /// Constructor.
    function SecretStoreService(address[] initialAuthorities) AuthoritiesOwned(initialAuthorities) public {
    }
}
