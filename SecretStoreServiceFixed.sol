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
    /// Maximal (impossible) threshold value.
    uint constant internal MAX_THRESHOLD = 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF;

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

    /// Confirmation support.
    enum ConfirmationSupport { Confirmed, Unconfirmed, Impossible }

    /// Confirmations from authorities.
    struct Confirmations {
        address[] confirmedAuthorities;
        bytes32[] confirmations;
        mapping (bytes32 => uint) confirmationsSupport;
        uint maxConfirmationSupport;
    }

    /// Constructor.
    function AuthoritiesOwned(address[] initialAuthorities) internal {
        authorities = initialAuthorities;
    }

    /// Drain balance of sender authority.
    function drain() public onlyAuthority onlyWithBalance {
        uint balance = balances[msg.sender];
        balances[msg.sender] = 0;
        msg.sender.transfer(balance);
    }

    /// Deposit equal share of amount to each of authorities.
    function deposit(uint amount) internal {
        uint authorityShare = amount / authorities.length;
        for (uint i = 0; i < authorities.length - 1; i++) {
            address authority = authorities[i];
            balances[authority] += authorityShare;

            amount = amount - authorityShare;
        }

        address lastAuthority = authorities[authorities.length - 1];
        balances[lastAuthority] += amount;
    }

    /// Is authority?
    function isAuthority(address authority) internal view returns (bool) {
        for (uint i = 0; i < authorities.length; i++) {
            if (authority == authorities[i]) {
                return true;
            }
        }
        return false;
    }

    /// Get authorities.
    function getAuthoritiesInternal() view public returns (address[]) {
        return authorities;
    }

    /// Get authorities count.
    function getAuthoritiesCountInternal() view internal returns (uint) {
        return authorities.length;
    }

    /// Check if authority has already voted.
    function isConfirmedByAuthority(
        Confirmations storage confirmations,
        address authority
    ) view internal returns (bool)
    {
        for (uint i = 0; i < confirmations.confirmedAuthorities.length; ++i) {
            if (confirmations.confirmedAuthorities[i] == authority) {
                return true;
            }
        }
        return false;
    }

    /// Insert authority confirmation.
    function insertConfirmation(
        Confirmations storage confirmations,
        address authority,
        bytes32 confirmation
    ) internal
    {
        // check if authority has already voted
        if (isConfirmedByAuthority(confirmations, authority)) {
            return;
        }

        // insert confirmation
        uint confirmationSupport = confirmations.confirmationsSupport[confirmation] + 1;
        confirmations.confirmedAuthorities.push(authority);
        confirmations.confirmationsSupport[confirmation] = confirmationSupport;
        if (confirmationSupport == 1) {
            confirmations.confirmations.push(confirmation);
        }
        if (confirmationSupport > confirmations.maxConfirmationSupport) {
            confirmations.maxConfirmationSupport = confirmationSupport;
        }
    }

    /// Check if confirmation is supported by enough nodes.
    function checkConfirmationSupport(
        Confirmations storage confirmations,
        bytes32 confirmation,
        uint threshold
    ) internal view returns (ConfirmationSupport)
    {
        // check if passed confirmation has received enough support
        if (threshold + 1 <= confirmations.confirmationsSupport[confirmation]) {
            return ConfirmationSupport.Confirmed;
        }

        // check if max confirmation CAN receive enough support
        uint authoritiesLeft = getAuthoritiesCountInternal() - confirmations.confirmedAuthorities.length;
        if (threshold + 1 > confirmations.maxConfirmationSupport + authoritiesLeft) {
            return ConfirmationSupport.Impossible;
        }

        return ConfirmationSupport.Unconfirmed;
    }

    /// Insert and check authority confirmation with threshold.
    function insertConfirmationWithThreshold(
        Confirmations storage confirmations,
        Confirmations storage thresholdConfirmations,
        uint thresholdThreshold,
        address authority,
        uint threshold,
        bytes32 confirmation
    ) internal returns (ConfirmationSupport)
    {
        // insert threshold confirmation && confirmation itself
        bytes32 thresholdConfirmation = bytes32(threshold);
        insertConfirmation(confirmations, authority, confirmation);
        insertConfirmation(thresholdConfirmations, authority, thresholdConfirmation);

        // we need to agree upon threshold first
        // => only pass if threshold is confirmed
        ConfirmationSupport thresholdConfirmationSupport = checkConfirmationSupport(thresholdConfirmations,
            thresholdConfirmation, thresholdThreshold);
        if (thresholdConfirmationSupport == ConfirmationSupport.Unconfirmed ||
            thresholdConfirmationSupport == ConfirmationSupport.Impossible) {
            return thresholdConfirmationSupport;
        }

        // check confirmation support
        return checkConfirmationSupport(confirmations, confirmation, threshold);
    }

    /// Clear internal confirmations mappings.
    function clearConfirmations(Confirmations storage confirmations) internal {
        for (uint i = 0; i < confirmations.confirmations.length; ++i) {
            delete confirmations.confirmationsSupport[confirmations.confirmations[i]];
        }
        delete confirmations.confirmations;
        delete confirmations.confirmedAuthorities;
        confirmations.maxConfirmationSupport = 0;
    }

    /// Remove request id from array.
    function removeRequestKey(bytes32[] storage requests, bytes32 request) internal {
        for (uint i = 0; i < requests.length; ++i) {
            if (requests[i] == request) {
                for (uint j = i + 1; j < requests.length; ++j) {
                    requests[j - 1] = requests[j];
                }
                delete requests[requests.length - 1];
                requests.length = requests.length - 1;
                break;
            }
        }
    }

    /// Compute address from public key.
    function computeAddress(bytes publicKey) internal pure returns (address) {
        return address(uint(keccak256(publicKey)) & 0x00FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF);
    }

    /// Authorities.
    address[] private authorities;
    /// Balances of authorities.
    mapping (address => uint) private balances;
}


/// Authorities owned fee manage.
contract AuthoritiesOwnedFeeManager is AuthoritiesOwned {
    /// Only pass when fee is paid.
    modifier whenFeePaid(string id) {
        Fee storage fee = fees[id];
        require (fee.value != 0);
        require (msg.value >= fee.value);
        _;
    }

    /// Only when non-zero fee is proposed.
    modifier whenNonZeroFeeIsProposed(uint newValue) {
        require (newValue != 0);
        _;
    }

    /// Only when _new_ fee is proposed.
    modifier whenNewFeeIsProposed(string id, uint newValue) {
        require (fees[id].value != newValue);
        _;
    }

    /// Only when _new_ vote is proposed.
    modifier whenNewVoteIsProposed(string id, uint newValue) {
        require (fees[id].votes[msg.sender] != newValue);
        _;
    }

    /// Single fee.
    struct Fee {
        /// Active value.
        uint value;
        /// Active votes.
        mapping (address => uint) votes;
    }

    /// Get actual fee value.
    function getFee(string id) view public returns (uint) {
        Fee storage fee = fees[id];
        require(fee.value != 0);
        return fee.value;
    }

    /// Vote for fee change proposal.
    function voteFee(string id, uint value) public onlyAuthority
        whenNonZeroFeeIsProposed(value)
        whenNewFeeIsProposed(id, value)
        whenNewVoteIsProposed(id, value)
    {
        // update vote
        Fee storage fee = fees[id];
        require(fee.value != 0);
        fee.votes[msg.sender] = value;

        // check if there's majority agreement
        if (!checkFeeVoting(fee, value)) {
            return;
        }

        // ...and change actual fee
        fee.value = value;
    }

    /// Register fee.
    function registerFee(string id, uint value) internal {
        fees[id].value = value;
    }

    /// Check if fee voting has finished.
    function checkFeeVoting(Fee storage fee, uint lastVote) view internal returns (bool) {
        uint confirmations = 0;
        address[] memory authorities = getAuthoritiesInternal();
        uint threshold = authorities.length / 2 + 1;
        for (uint i = 0; i < authorities.length; ++i) {
            if (fee.votes[authorities[i]] == lastVote) {
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

    /// All registered fees.
    mapping (string => Fee) internal fees;
}

/// Server key generation service contract. This contract allows to generate SecretStore KeyPairs, which
/// could be used later to sign messages or to link with document keys.
contract ServerKeyGenerationService is AuthoritiesOwnedFeeManager {
    /// Server key generation fee id.
    string constant public SKGFEE = "SKGFEE";

    /// Server key generation request.
    struct ServerKeyGenerationRequest {
        bool isActive;
        address author;
        uint threshold;
        Confirmations confirmations;
    }

    /// When sever key generation request is received.
    event ServerKeyGenerationRequested(bytes32 serverKeyId, address author, uint threshold);
    /// When server key is generated.
    event ServerKeyGenerated(bytes32 indexed serverKeyId, bytes serverKeyPublic);
    /// When error occurs during server key generation.
    event ServerKeyGenerationError(bytes32 indexed serverKeyId);

    /// Constructor.
    function ServerKeyGenerationService() public {
        registerFee(SKGFEE, 1 ether);
    }

    /// Request new server key generation. Generated key will be published via ServerKeyReady event when available.
    function generateServerKey(bytes32 serverKeyId, uint threshold) public payable whenFeePaid(SKGFEE) {
        ServerKeyGenerationRequest storage request = serverKeyGenerationRequests[serverKeyId];
        require(!request.isActive);
        require(threshold + 1 <= getAuthoritiesCountInternal());
        deposit(msg.value);

        request.isActive = true;
        request.author = msg.sender;
        request.threshold = threshold;
        serverKeyGenerationRequestsKeys.push(serverKeyId);

        ServerKeyGenerationRequested(serverKeyId, msg.sender, threshold);
    }

    /// Called when generation/retrieval is reported by one of authorities.
    function serverKeyGenerated(
        bytes32 serverKeyId,
        bytes serverKeyPublic) public onlyAuthority
    {
        // check if request still active
        ServerKeyGenerationRequest storage request = serverKeyGenerationRequests[serverKeyId];
        if (!request.isActive) {
            return;
        }

        // insert confirmation
        bytes32 confirmation = keccak256(serverKeyPublic);
        insertConfirmation(request.confirmations, msg.sender, confirmation);

        // ...and check if there are enough confirmations
        ConfirmationSupport confirmationSupport = checkConfirmationSupport(request.confirmations, confirmation,
            getAuthoritiesCountInternal() - 1);
        if (confirmationSupport == ConfirmationSupport.Unconfirmed) {
            return;
        }

        // delete request and fire event
        deleteServerKeyGenerationRequest(serverKeyId, request);
        if (confirmationSupport == ConfirmationSupport.Confirmed) {
            ServerKeyGenerated(serverKeyId, serverKeyPublic);
        } else { // ConfirmationSupport.Impossible
            ServerKeyGenerationError(serverKeyId);
        }
    }

    /// Called when error occurs during server key generation/retrieval.
    function serverKeyGenerationError(bytes32 serverKeyId) public onlyAuthority {
        // check if request still active
        ServerKeyGenerationRequest storage request = serverKeyGenerationRequests[serverKeyId];
        if (!request.isActive) {
            return;
        }

        // any error in key generation is fatal, because we need all key servers to participate in generation
        // => delete request and fire event
        deleteServerKeyGenerationRequest(serverKeyId, request);
        ServerKeyGenerationError(serverKeyId);
    }

    /// Get count of pending server key generation requests.
    function serverKeyGenerationRequestsCount() view public returns (uint) {
        return serverKeyGenerationRequestsKeys.length;
    }

    /// Get server key generation request with given index.
    /// Returns: (serverKeyId, author, threshold)
    function getServerKeyGenerationRequest(uint index) view public returns (bytes32, address, uint) {
        require(index < serverKeyGenerationRequestsKeys.length);
        bytes32 serverKeyId = serverKeyGenerationRequestsKeys[index];
        ServerKeyGenerationRequest storage request = serverKeyGenerationRequests[serverKeyId];
        require(request.isActive);
        return (
            serverKeyId,
            request.author,
            request.threshold
        );
    }

    /// Get server key generation request confirmation status.
    function getServerKeyGenerationRequestConfirmationStatus(bytes32 serverKeyId, address authority) view public returns (bool) {
        ServerKeyGenerationRequest storage request = serverKeyGenerationRequests[serverKeyId];
        return request.isActive && !isConfirmedByAuthority(request.confirmations, authority);
    }

    /// Delete server key request.
    function deleteServerKeyGenerationRequest(bytes32 serverKeyId, ServerKeyGenerationRequest storage request) private {
        clearConfirmations(request.confirmations);
        removeRequestKey(serverKeyGenerationRequestsKeys, serverKeyId);
        delete serverKeyGenerationRequests[serverKeyId];
    }

    /// Pending generation requests.
    mapping (bytes32 => ServerKeyGenerationRequest) serverKeyGenerationRequests;
    /// Pending generation requests keys.
    bytes32[] serverKeyGenerationRequestsKeys;
}


/// Server key retrieval service contract. This contract allows to retrieve previously generated server keys.
/// Server key (its public part) is returned in unencrypted form to any requester => only one active request
/// is possible at a time.
contract ServerKeyRetrievalService is AuthoritiesOwnedFeeManager {
    /// Server key retrieval fee id.
    string constant public SKRFEE = "SKRFEE";

    /// Server key retrieval request.
    struct ServerKeyRetrievalRequest {
        bool isActive;
        Confirmations thresholdConfirmations;
        Confirmations confirmations;
    }

    /// When sever key retrieval request is received.
    event ServerKeyRetrievalRequested(bytes32 serverKeyId);
    /// When server key is retrieved.
    event ServerKeyRetrieved(bytes32 indexed serverKeyId, bytes serverKeyPublic);
    /// When error occurs during server key retrieval.
    event ServerKeyRetrievalError(bytes32 indexed serverKeyId);

    /// Constructor.
    function ServerKeyRetrievalService() public {
        registerFee(SKRFEE, 1 ether);
    }

    /// Retrieve existing server key. Retrieved key will be published via ServerKeyRetrieved or ServerKeyRetrievalError.
    function retrieveServerKey(bytes32 serverKeyId) public payable whenFeePaid(SKRFEE) {
        ServerKeyRetrievalRequest storage request = serverKeyRetrievalRequests[serverKeyId];
        require(!request.isActive);
        deposit(msg.value);

        // we do not know exact threshold value here && we can not blindly trust the first response
        // => we should agree upon two values: threshold && server key itself
        // => assuming that all authorities will eventually respond with value/error, we will wait for:
        // 1) at least 50% + 1 authorities agreement on the same threshold value
        // 2) after threshold is agreed, we will wait for threshold + 1 values of server key

        request.isActive = true;
        serverKeyRetrievalRequestsKeys.push(serverKeyId);

        ServerKeyRetrievalRequested(serverKeyId);
    }

    /// Called when retrieval is reported by one of authorities.
    function serverKeyRetrieved(bytes32 serverKeyId, bytes serverKeyPublic, uint threshold) public onlyAuthority {
        // check if request still active
        ServerKeyRetrievalRequest storage request = serverKeyRetrievalRequests[serverKeyId];
        if (!request.isActive) {
            return;
        }

        // insert and check confirmation
        bytes32 confirmation = keccak256(serverKeyPublic);
        ConfirmationSupport confirmationSupport = insertConfirmationWithThreshold(
            request.confirmations,
            request.thresholdConfirmations,
            getAuthoritiesCountInternal() / 2,
            msg.sender,
            threshold,
            confirmation);
        if (confirmationSupport == ConfirmationSupport.Unconfirmed) {
            return;
        }

        // delete request and fire event
        deleteServerKeyRetrievalRequest(serverKeyId, request);
        if (confirmationSupport == ConfirmationSupport.Confirmed) {
            ServerKeyRetrieved(serverKeyId, serverKeyPublic);
        } else { // ConfirmationSupport.Impossible
            ServerKeyRetrievalError(serverKeyId);
        }
    }

    /// Called when error occurs during server key retrieval.
    function serverKeyRetrievalError(bytes32 serverKeyId) public onlyAuthority {
        // check if request still active
        ServerKeyRetrievalRequest storage request = serverKeyRetrievalRequests[serverKeyId];
        if (!request.isActive) {
            return;
        }

        // all key servers in SS with auto-migration enabled should have a share for every key
        // => we could make an error fatal, but let's tolerate such issues
        // => insert invalid confirmation and check if there are enough confirmations
        bytes32 confirmation = bytes32(0);
        ConfirmationSupport confirmationSupport = insertConfirmationWithThreshold(
            request.confirmations,
            request.thresholdConfirmations,
            getAuthoritiesCountInternal() / 2,
            msg.sender,
            MAX_THRESHOLD,
            confirmation);
        if (confirmationSupport == ConfirmationSupport.Unconfirmed) {
            return;
        }

        // delete request and fire event
        deleteServerKeyRetrievalRequest(serverKeyId, request);
        ServerKeyRetrievalError(serverKeyId);
    }

    /// Get count of pending server key retrieval requests.
    function serverKeyRetrievalRequestsCount() view public returns (uint) {
        return serverKeyRetrievalRequestsKeys.length;
    }

    /// Get server key retrieval request with given index.
    /// Returns: (serverKeyId)
    function getServerKeyRetrievalRequest(uint index) view public returns (bytes32) {
        require(index < serverKeyRetrievalRequestsKeys.length);
        bytes32 serverKeyId = serverKeyRetrievalRequestsKeys[index];
        ServerKeyRetrievalRequest storage request = serverKeyRetrievalRequests[serverKeyId];
        require(request.isActive);
        return (
            serverKeyId
        );
    }

    /// Get server key retrieval request confirmation status.
    function getServerKeyRetrievalRequestConfirmationStatus(bytes32 serverKeyId, address authority) view public returns (bool) {
        ServerKeyRetrievalRequest storage request = serverKeyRetrievalRequests[serverKeyId];
        return request.isActive && !isConfirmedByAuthority(request.confirmations, authority);
    }

    /// Delete server key retrieval request.
    function deleteServerKeyRetrievalRequest(bytes32 serverKeyId, ServerKeyRetrievalRequest storage request) private {
        clearConfirmations(request.confirmations);
        clearConfirmations(request.thresholdConfirmations);
        removeRequestKey(serverKeyRetrievalRequestsKeys, serverKeyId);
        delete serverKeyRetrievalRequests[serverKeyId];
    }

    /// Pending generation requests.
    mapping (bytes32 => ServerKeyRetrievalRequest) serverKeyRetrievalRequests;
    /// Pending generation requests keys.
    bytes32[] serverKeyRetrievalRequestsKeys;
}


/// Document key store service contract. This contract allows to store externally generated document key, which
/// could be retrieved later.
contract DocumentKeyStoreService is AuthoritiesOwnedFeeManager {
    /// Document key store fee id.
    string constant public DKSFEE = "DKSFEE";

    /// Document key store request.
    struct DocumentKeyStoreRequest {
        bool isActive;
        address author;
        bytes commonPoint;
        bytes encryptedPoint;
        Confirmations confirmations;
    }

    /// When document key store request is received.
    event DocumentKeyStoreRequested(bytes32 serverKeyId, address author, bytes commonPoint, bytes encryptedPoint);
    /// When document key is stored.
    event DocumentKeyStored(bytes32 indexed serverKeyId);
    /// When error occurs during document key store.
    event DocumentKeyStoreError(bytes32 indexed serverKeyId);

    /// Constructor.
    function DocumentKeyStoreService() public {
        registerFee(DKSFEE, 1 ether);
    }

    /// Request document key store.
    function storeDocumentKey(bytes32 serverKeyId, bytes commonPoint, bytes encryptedPoint) public payable whenFeePaid(DKSFEE) {
        DocumentKeyStoreRequest storage request = documentKeyStoreRequests[serverKeyId];
        require(!request.isActive);
        deposit(msg.value);

        request.isActive = true;
        request.author = msg.sender;
        request.commonPoint = commonPoint;
        request.encryptedPoint = encryptedPoint;
        documentKeyStoreRequestsKeys.push(serverKeyId);

        DocumentKeyStoreRequested(serverKeyId, msg.sender, commonPoint, encryptedPoint);
    }

    /// Called when store is reported by one of authorities.
    function documentKeyStored(bytes32 serverKeyId) public onlyAuthority {
        // check if request still active
        DocumentKeyStoreRequest storage request = documentKeyStoreRequests[serverKeyId];
        if (!request.isActive) {
            return;
        }

        // insert confirmation
        bytes32 confirmation = bytes32(0);
        insertConfirmation(request.confirmations, msg.sender, confirmation);

        // ...and check if there are enough confirmations (all authorities must confirm)
        ConfirmationSupport confirmationSupport = checkConfirmationSupport(request.confirmations, confirmation,
            getAuthoritiesCountInternal() - 1);
        if (confirmationSupport == ConfirmationSupport.Unconfirmed) {
            return;
        }

        // delete request and fire event
        deleteDocumentKeyStoreRequest(serverKeyId, request);
        if (confirmationSupport == ConfirmationSupport.Confirmed) {
            DocumentKeyStored(serverKeyId);
        } else { // ConfirmationSupport.Impossible
            DocumentKeyStoreError(serverKeyId);
        }
    }

    /// Called when error occurs during document key store.
    function documentKeyStoreError(bytes32 serverKeyId) public onlyAuthority {
        // check if request still active
        DocumentKeyStoreRequest storage request = documentKeyStoreRequests[serverKeyId];
        if (!request.isActive) {
            return;
        }

        // any error in key store is fatal, because we need all key servers to participate in store
        // => delete request and fire event
        deleteDocumentKeyStoreRequest(serverKeyId, request);
        DocumentKeyStoreError(serverKeyId);
    }

    /// Get count of pending document key store requests.
    function documentKeyStoreRequestsCount() view public returns (uint) {
        return documentKeyStoreRequestsKeys.length;
    }

    /// Get document key store request with given index.
    /// Returns: (serverKeyId, author, commonPoint, encryptedPoint)
    function getDocumentKeyStoreRequest(uint index) view public returns (bytes32, address, bytes, bytes) {
        require(index < documentKeyStoreRequestsKeys.length);
        bytes32 serverKeyId = documentKeyStoreRequestsKeys[index];
        DocumentKeyStoreRequest storage request = documentKeyStoreRequests[serverKeyId];
        require(request.isActive);
        return (
            serverKeyId,
            request.author,
            request.commonPoint,
            request.encryptedPoint
        );
    }

    /// Get document key store request confirmation status.
    function getDocumentKeyStoreRequestConfirmationStatus(bytes32 serverKeyId, address authority) view public returns (bool) {
        DocumentKeyStoreRequest storage request = documentKeyStoreRequests[serverKeyId];
        return request.isActive && !isConfirmedByAuthority(request.confirmations, authority);
    }

    /// Delete document key store request.
    function deleteDocumentKeyStoreRequest(bytes32 serverKeyId, DocumentKeyStoreRequest storage request) private {
        clearConfirmations(request.confirmations);
        removeRequestKey(documentKeyStoreRequestsKeys, serverKeyId);
        delete documentKeyStoreRequests[serverKeyId];
    }

    /// Pending store requests.
    mapping (bytes32 => DocumentKeyStoreRequest) documentKeyStoreRequests;
    /// Pending store requests keys.
    bytes32[] documentKeyStoreRequestsKeys;
}

/// Document key retrieval service contract. This contract allows to retrieve previously stored document key.
contract DocumentKeyShadowRetrievalService is AuthoritiesOwnedFeeManager {
    /// Document key retrieval fee id.
    string constant public DKSRFEE = "DKSRFEE";

    /// Document key shadow retrieval request.
    struct DocumentKeyShadowRetrievalRequest {
        bool isActive;
        bytes32 serverKeyId;
        bytes requesterPublic;
        Confirmations thresholdConfirmations;
        bool isCommonRetrievalCompleted;
        uint threshold;
        bytes32[] dataKeys;
        mapping (bytes32 => DocumentKeyShadowRetrievalData) data;
    }

    /// Document key retrieval data.
    struct DocumentKeyShadowRetrievalData {
        bool isActive;
        address[] participants;
        address[] reported;
    }

    /// When document key common-portion retrieval request is received.
    event DocumentKeyCommonRetrievalRequested(bytes32 serverKeyId, address requester);
    /// When document key retrieval request is received.
    event DocumentKeyPersonalRetrievalRequested(bytes32 serverKeyId, bytes requesterPublic);
    /// When document key common portion is retrieved.
    event DocumentKeyCommonRetrieved(bytes32 indexed serverKeyId, address indexed requester, bytes commonPoint, uint threshold);
    /// When document key personal portion is retrieved.
    event DocumentKeyPersonalRetrieved(bytes32 indexed serverKeyId, address indexed requester, bytes decryptedSecret, bytes shadow);
    /// When error occurs during document key retrieval.
    event DocumentKeyShadowRetrievalError(bytes32 indexed serverKeyId, address indexed requester);

    /// Constructor.
    function DocumentKeyShadowRetrievalService() public {
        registerFee(DKSRFEE, 1 ether);
    }

    /// Request document key retrieval.
    function retrieveDocumentKeyShadow(bytes32 serverKeyId, bytes requesterPublic) public payable whenFeePaid(DKSRFEE) {
        require(computeAddress(requesterPublic) == msg.sender);

        bytes32 retrievalId = keccak256(serverKeyId, msg.sender);
        DocumentKeyShadowRetrievalRequest storage request = documentKeyShadowRetrievalRequests[retrievalId];
        require(!request.isActive);
        deposit(msg.value);

        // we do not know exact threshold value here && we can not blindly trust the first response
        // => we should agree upon two values: threshold && document key itself
        // => assuming that all authorities will eventually respond with value/error, we will wait for:
        // 1) at least 50% + 1 authorities agreement on the same threshold value
        // 2) after threshold is agreed, we will wait for threshold + 1 values of document key

        // the data required to compute document key is the triple { commonPoint, encryptedPoint, shadowPoints[] }
        // this data is computed on threshold + 1 nodes only
        // retrieval consists of two phases:
        // 1) every authority that is seeing retrieval request, publishes { commonPoint, encryptedPoint, threshold }
        // 2) master node starts decryption session
        // 2.1) every node participating in decryption session publishes { address[], shadow }
        // 2.2) once there are threshold + 1 confirmations of { address[], shadow } from exactly address[] authorities, we are publishing the key

        request.isActive = true;
        request.serverKeyId = serverKeyId;
        request.requesterPublic = requesterPublic;
        request.isCommonRetrievalCompleted = false;
        documentKeyShadowRetrievalRequestsKeys.push(retrievalId);

        DocumentKeyCommonRetrievalRequested(serverKeyId, msg.sender);
    }

    /// Called when common data is reported by one of authorities.
    function documentKeyCommonRetrieved(bytes32 serverKeyId, address requester, bytes commonPoint, uint threshold) public onlyAuthority {
        // check if request still active
        bytes32 retrievalId = keccak256(serverKeyId, requester);
        DocumentKeyShadowRetrievalRequest storage request = documentKeyShadowRetrievalRequests[retrievalId];
        if (!request.isActive || request.isCommonRetrievalCompleted) {
            return;
        }

        // insert confirmation
        bytes32 thresholdConfirmation = keccak256(commonPoint, threshold);
        insertConfirmation(request.thresholdConfirmations, msg.sender, thresholdConfirmation);

        // ...and check if there are enough confirmations
        ConfirmationSupport thresholdConfirmationSupport = checkConfirmationSupport(request.thresholdConfirmations,
            thresholdConfirmation, getAuthoritiesCountInternal() / 2);
        if (thresholdConfirmationSupport == ConfirmationSupport.Unconfirmed) {
            return;
        }

        // if threshold confirmation isn't possible => retrieval is also impossible
        if (thresholdConfirmationSupport == ConfirmationSupport.Impossible) {
            deleteDocumentKeyShadowRetrievalRequest(retrievalId, request);
            DocumentKeyShadowRetrievalError(serverKeyId, requester);
            return;
        }

        // else => remember required data
        request.isCommonRetrievalCompleted = true;
        request.threshold = threshold;

        // ...and publish common data (also signal 'master' key server to start decryption)
        DocumentKeyCommonRetrieved(serverKeyId, requester, commonPoint, threshold);
        DocumentKeyPersonalRetrievalRequested(serverKeyId, request.requesterPublic);
    }

    /// Called when 'personal' data is reported by one of authorities.
    function documentKeyPersonalRetrieved(bytes32 serverKeyId, address requester, address[] participants, bytes decryptedSecret, bytes shadow) public onlyAuthority {
        // check if request still active
        bytes32 retrievalId = keccak256(serverKeyId, requester);
        DocumentKeyShadowRetrievalRequest storage request = documentKeyShadowRetrievalRequests[retrievalId];
        if (!request.isActive) {
            return;
        }
        require(request.isCommonRetrievalCompleted);

        // there must be exactly threshold + 1 participants
        require(request.threshold + 1 == participants.length);

        // authority must have an entry in participants
        bool isParticipant = false;
        for (uint i = 0; i < participants.length; ++i) {
            if (participants[i] == msg.sender) {
                isParticipant = true;
                break;
            }
        }
        require(isParticipant);

        // order of participants matter => all reporters must respond with equally-ordered participants array
        bytes32 retrievalDataId = keccak256(participants, decryptedSecret);
        DocumentKeyShadowRetrievalData storage data = request.data[retrievalDataId];
        if (!data.isActive) {
            request.dataKeys.push(retrievalDataId);

            data.isActive = true;
            data.participants = participants;
        } else {
            for (uint j = 0; j < data.reported.length; ++j) {
                if (data.reported[j] == msg.sender) {
                    return;
                }
            }
        }

        // remember result
        data.reported.push(msg.sender);

        // publish personal portion
        DocumentKeyPersonalRetrieved(serverKeyId, requester, decryptedSecret, shadow);

        // check if all participants have responded
        if (request.threshold + 1 != data.reported.length) {
            return;
        }

        // delete request and publish key
        deleteDocumentKeyShadowRetrievalRequest(retrievalId, request);
        return;
    }

    /// Called when error occurs during document key retrieval.
    function documentKeyShadowRetrievalError(bytes32 serverKeyId, address requester) public onlyAuthority {
        // check if request still active
        bytes32 retrievalId = keccak256(serverKeyId, requester);
        DocumentKeyShadowRetrievalRequest storage request = documentKeyShadowRetrievalRequests[serverKeyId];
        if (!request.isActive) {
            return;
        }

        // error on common data retrieval step is treated like a voting for non-existant common data
        if (!request.isCommonRetrievalCompleted) {
            // insert confirmation
            bytes32 thresholdConfirmation = bytes32(0);
            insertConfirmation(request.thresholdConfirmations, msg.sender, thresholdConfirmation);

            // ...and check if there are enough confirmations
            ConfirmationSupport thresholdConfirmationSupport = checkConfirmationSupport(request.thresholdConfirmations,
                thresholdConfirmation, getAuthoritiesCountInternal() / 2);
            if (thresholdConfirmationSupport == ConfirmationSupport.Unconfirmed) {
                return;
            }

            // delete request and fire event
            deleteDocumentKeyShadowRetrievalRequest(retrievalId, request);
            DocumentKeyShadowRetrievalError(serverKeyId, requester);
            return;
        }

        // when error occurs on personal retrieval step, we just ignore it, hoping for retry
        // TODO: not correct - what if access changes to access denied???
    }

    /// Get count of pending document key retrieval requests.
    function documentKeyShadowRetrievalRequestsCount() view public returns (uint) {
        return documentKeyShadowRetrievalRequestsKeys.length;
    }

    /// Get document key retrieval request with given index.
    /// Returns: (serverKeyId, requesterPublic, isCommonRetrievalCompleted)
    function getDocumentKeyShadowRetrievalRequest(uint index) view public returns (bytes32, bytes, bool) {
        require(index < documentKeyShadowRetrievalRequestsKeys.length);
        bytes32 retrievalId = documentKeyShadowRetrievalRequestsKeys[index];
        DocumentKeyShadowRetrievalRequest storage request = documentKeyShadowRetrievalRequests[retrievalId];
        require(request.isActive);
        // TODO: we do not process pending requests which has returned isConfirmed == true => return false when threshold has completed
        return (
            request.serverKeyId,
            request.requesterPublic,
            request.isCommonRetrievalCompleted
        );
    }

    /// Get document key store request confirmation status.
    function getDocumentKeyShadowRetrievalRequestConfirmationStatus(bytes32 serverKeyId, address requester, address authority) view public returns (bool) {
        bytes32 retrievalId = keccak256(serverKeyId, requester);
        DocumentKeyShadowRetrievalRequest storage request = documentKeyShadowRetrievalRequests[retrievalId];
        return request.isActive && !isConfirmedByAuthority(request.thresholdConfirmations, authority);
    }

    /// Delete document key retrieval request.
    function deleteDocumentKeyShadowRetrievalRequest(bytes32 retrievalId, DocumentKeyShadowRetrievalRequest storage request) private {
        for (uint i = 0; i < request.dataKeys.length; ++i) {
            DocumentKeyShadowRetrievalData storage data = request.data[request.dataKeys[i]];
            delete data.participants;
            delete data.reported;
        }
        clearConfirmations(request.thresholdConfirmations);
        removeRequestKey(documentKeyShadowRetrievalRequestsKeys, retrievalId);
        delete request.dataKeys;
        delete documentKeyShadowRetrievalRequests[retrievalId];
    }

    /// Pending retrieval requests.
    mapping (bytes32 => DocumentKeyShadowRetrievalRequest) documentKeyShadowRetrievalRequests;
    /// Pending retrieval requests keys.
    bytes32[] documentKeyShadowRetrievalRequestsKeys;
}


/// Secret store service contract.
contract SecretStoreService is AuthoritiesOwned, AuthoritiesOwnedFeeManager,
    ServerKeyGenerationService, ServerKeyRetrievalService,
    DocumentKeyStoreService, DocumentKeyShadowRetrievalService {
    /// Constructor.
    function SecretStoreService(address[] initialAuthorities) AuthoritiesOwned(initialAuthorities) public {
    }
}
