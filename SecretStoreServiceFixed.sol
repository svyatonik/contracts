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
    /// Only pass when fee is paid.
    modifier whenFeePaid(uint256 amount) {
        require(msg.value >= amount);
        _;
    }

    /// Only pass when 'valid' public is passed.
    modifier validPublic(bytes publicKey) {
        require(publicKey.length == 64);
        _;
    }

    /// Confirmation support.
    enum ConfirmationSupport { Confirmed, Unconfirmed, Impossible }

    /// Confirmations from authorities.
    struct Confirmations {
        /// We only support up to 256 authorities. If bit is set, this means that authority
        /// has already voted for some confirmation (we do not care about exact confirmation).
        uint256 confirmedAuthorities;
        /// Number of confirmed authorities.
        uint8 confirmedAuthoritiesCount;
        /// Confirmation => number of supporting authorities mapping
        mapping (bytes32 => uint8) confirmationsSupport;
        /// Maximal support of single confirmation.
        uint8 maxConfirmationSupport;
        /// All confirmation that are in confirmationsSupport. In ideal world, when all
        //// authorities are working corretly, there'll be 1 confirmation. Max 256 confirmations.
        bytes32[] confirmations;
    }

    /// Constructor.
    function AuthoritiesOwned(address[] authorities) internal {
        // checking for duplicates is the deployer duty
        require(authorities.length > 0 && authorities.length <= 256);
        for (uint8 i = 0; i < authorities.length; ++i) {
            address authority = authorities[i];
            indexes[authority] = i + 1;
            addresses.push(authority);
        }
    }

    /// Require authority index.
    function requireAuthority(address authority) view internal returns (uint8) {
        uint8 index = indexes[authority];
        require(index != 0);
        return index - 1;
    } 

    /// Drain balance of sender authority.
    function drain() public {
        uint8 authorityIndex = requireAuthority(msg.sender);
        uint256 balance = balances[authorityIndex];
        require(balance != 0);
        balances[authorityIndex] = 0;
        msg.sender.transfer(balance);
    }

    /// Deposit equal share of amount to each of authorities.
    function deposit(uint256 amount) internal {
        uint256 authorityShare = amount / addresses.length;
        for (uint256 i = 0; i < addresses.length - 1; i++) {
            balances[i] += authorityShare;
            amount = amount - authorityShare;
        }

        balances[addresses.length - 1] += amount;
    }

    /// Check if authority has already voted.
    function isConfirmedByAuthority(Confirmations storage confirmations, uint8 authorityIndex) view internal returns (bool) {
        return ((confirmations.confirmedAuthorities & (uint256(1) << authorityIndex)) != 0);
    }

    /// Insert authority confirmation.
    function insertConfirmation(Confirmations storage confirmations, uint8 authorityIndex, uint256 threshold, bytes32 confirmation) internal returns (ConfirmationSupport) {
        // check if authority has already voted
        if (isConfirmedByAuthority(confirmations, authorityIndex)) {
            return ConfirmationSupport.Unconfirmed;
        }

        // insert confirmation
        uint8 confirmationSupport = confirmations.confirmationsSupport[confirmation] + 1;
        confirmations.confirmedAuthorities |= uint256(1) << authorityIndex;
        confirmations.confirmedAuthoritiesCount += 1;
        confirmations.confirmationsSupport[confirmation] = confirmationSupport;
        if (confirmationSupport == 1) {
            confirmations.confirmations.push(confirmation);
        }
        if (confirmationSupport < confirmations.maxConfirmationSupport) {
            return ConfirmationSupport.Unconfirmed;
        }
        confirmations.maxConfirmationSupport = confirmationSupport;
  
        // check if passed confirmation has received enough support
        if (threshold + 1 <= confirmationSupport) {
            return ConfirmationSupport.Confirmed;
        }

        // check if max confirmation CAN receive enough support
        uint256 authoritiesLeft = addresses.length - confirmations.confirmedAuthoritiesCount;
        if (threshold + 1 > confirmations.maxConfirmationSupport + authoritiesLeft) {
            return ConfirmationSupport.Impossible;
        }

        return ConfirmationSupport.Unconfirmed;
    }

    /// Clear internal confirmations mappings.
    function clearConfirmations(Confirmations storage confirmations) internal {
        for (uint256 i = 0; i < confirmations.confirmations.length; ++i) {
            delete confirmations.confirmationsSupport[confirmations.confirmations[i]];
        }
    }

    /// Remove request id from array.
    function removeRequestKey(bytes32[] storage requests, bytes32 request) internal {
        for (uint i = 0; i < requests.length; ++i) {
            if (requests[i] == request) {
                requests[i] = requests[requests.length - 1];
                requests.length = requests.length - 1;
                break;
            }
        }
    }

    /// Authorities indexes.
    mapping (address => uint8) public indexes;
    /// Authorities addresses.
    address[] public addresses;
    /// Balances of authorities.
    uint256[] public balances;
}


/// Server key generation service contract. This contract allows to generate SecretStore KeyPairs, which
/// could be used later to sign messages or to link with document keys.
contract ServerKeyGenerationService is AuthoritiesOwned {
    /// Server key generation fee.
    uint256 constant SKG_FEE = 100 finney;
    /// Maximal number of active server key generation requests. We're limiting this number to avoid
    /// infinite gas costs of some functions.
    uint256 constant SKG_MAX_REQUESTS = 16;

    /// Server key generation request.
    struct ServerKeyGenerationRequest {
        address author;
        uint256 threshold;
        Confirmations confirmations;
    }

    /// When sever key generation request is received.
    event ServerKeyGenerationRequested(bytes32 serverKeyId, address author, uint256 threshold);
    /// When server key is generated.
    event ServerKeyGenerated(bytes32 indexed serverKeyId, bytes serverKeyPublic);
    /// When error occurs during server key generation.
    event ServerKeyGenerationError(bytes32 indexed serverKeyId);

    /// Request new server key generation. Generated key will be published via ServerKeyReady event when available.
    function generateServerKey(bytes32 serverKeyId, uint256 threshold) public payable whenFeePaid(SKG_FEE) {
        // we can't process requests with invalid threshold
        require(threshold + 1 <= addresses.length);
        // check maximum number of requests
        require(serverKeyGenerationRequestsKeys.length < SKG_MAX_REQUESTS);

        ServerKeyGenerationRequest storage request = serverKeyGenerationRequests[serverKeyId];
        require(request.author == address(0));
        deposit(msg.value);

        request.author = msg.sender;
        request.threshold = threshold;
        serverKeyGenerationRequestsKeys.push(serverKeyId);

        ServerKeyGenerationRequested(serverKeyId, msg.sender, threshold);
    }

    /// Called when generation/retrieval is reported by one of authorities.
    function serverKeyGenerated(bytes32 serverKeyId, bytes serverKeyPublic) public validPublic(serverKeyPublic) {
        // check that it is called by authority
        uint8 authorityIndex = requireAuthority(msg.sender);

        // check if request still active
        ServerKeyGenerationRequest storage request = serverKeyGenerationRequests[serverKeyId];
        if (request.author == address(0)) {
            return;
        }

        // insert confirmation (we're waiting for confirmations from all authorities here)
        bytes32 confirmation = keccak256(serverKeyPublic);
        ConfirmationSupport confirmationSupport = insertConfirmation(request.confirmations, authorityIndex,
            addresses.length - 1, confirmation);

        // ...and check if there are enough confirmations
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
    function serverKeyGenerationError(bytes32 serverKeyId) public {
        // check that it is called by authority
        requireAuthority(msg.sender);

        // check if request still active
        ServerKeyGenerationRequest storage request = serverKeyGenerationRequests[serverKeyId];
        if (request.author == address(0)) {
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
    function getServerKeyGenerationRequest(uint256 index) view public returns (bytes32, address, uint256) {
        bytes32 serverKeyId = serverKeyGenerationRequestsKeys[index];
        ServerKeyGenerationRequest storage request = serverKeyGenerationRequests[serverKeyId];
        return (
            serverKeyId,
            request.author,
            request.threshold
        );
    }

    /// Get server key generation request confirmation status.
    function getServerKeyGenerationRequestConfirmationStatus(bytes32 serverKeyId, address authority) view public returns (bool) {
        uint8 authorityIndex = requireAuthority(authority);
        ServerKeyGenerationRequest storage request = serverKeyGenerationRequests[serverKeyId];
        return !isConfirmedByAuthority(request.confirmations, authorityIndex);
    }

    /// Delete server key request.
    function deleteServerKeyGenerationRequest(bytes32 serverKeyId, ServerKeyGenerationRequest storage request) private {
        clearConfirmations(request.confirmations);
        delete serverKeyGenerationRequests[serverKeyId];

        removeRequestKey(serverKeyGenerationRequestsKeys, serverKeyId);
    }

    /// Pending generation requests.
    mapping (bytes32 => ServerKeyGenerationRequest) serverKeyGenerationRequests;
    /// Pending generation requests keys.
    bytes32[] serverKeyGenerationRequestsKeys;
}


/// Server key retrieval service contract. This contract allows to retrieve previously generated server keys.
/// Server key (its public part) is returned in unencrypted form to any requester => only one active request
/// is possible at a time.
contract ServerKeyRetrievalService is AuthoritiesOwned {
    /// Server key retrieval fee.
    uint256 constant SKR_FEE = 100 finney;
    /// Maximal number of active server key retrieval requests. We're limiting this number to avoid
    /// infinite gas costs of some functions.
    uint256 constant SKR_MAX_REQUESTS = 16;

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

    /// Retrieve existing server key. Retrieved key will be published via ServerKeyRetrieved or ServerKeyRetrievalError.
    function retrieveServerKey(bytes32 serverKeyId) public payable whenFeePaid(SKR_FEE) {
        // check maximum number of requests
        require(serverKeyRetrievalRequestsKeys.length < SKR_MAX_REQUESTS);

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
    function serverKeyRetrieved(bytes32 serverKeyId, bytes serverKeyPublic, uint256 threshold) public validPublic(serverKeyPublic) {
        // check that it is called by authority
        uint8 authorityIndex = requireAuthority(msg.sender);

        // check if request still active
        ServerKeyRetrievalRequest storage request = serverKeyRetrievalRequests[serverKeyId];
        if (!request.isActive) {
            return;
        }

        // insert threshold confirmation && confirmation itself
        bytes32 confirmation = keccak256(serverKeyPublic);
        ConfirmationSupport confirmationSupport = insertServerKeyRetrievalConfirmation(
            request,
            authorityIndex,
            confirmation,
            threshold);
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
    function serverKeyRetrievalError(bytes32 serverKeyId) public {
        // check that it is called by authority
        uint8 authorityIndex = requireAuthority(msg.sender);

        // check if request still active
        ServerKeyRetrievalRequest storage request = serverKeyRetrievalRequests[serverKeyId];
        if (!request.isActive) {
            return;
        }

        // all key servers in SS with auto-migration enabled should have a share for every key
        // => we could make an error fatal, but let's tolerate such issues
        // => insert invalid confirmation and check if there are enough confirmations
        bytes32 confirmation = bytes32(0);
        ConfirmationSupport confirmationSupport = insertServerKeyRetrievalConfirmation(
            request,
            authorityIndex,
            confirmation,
            0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF);
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
        bytes32 serverKeyId = serverKeyRetrievalRequestsKeys[index];
        return (serverKeyId);
    }

    /// Get server key retrieval request confirmation status.
    function getServerKeyRetrievalRequestConfirmationStatus(bytes32 serverKeyId, address authority) view public returns (bool) {
        uint8 authorityIndex = requireAuthority(authority);
        ServerKeyRetrievalRequest storage request = serverKeyRetrievalRequests[serverKeyId];
        return !isConfirmedByAuthority(request.confirmations, authorityIndex);
    }

    /// Insert both threshold and public confirmation.
    function insertServerKeyRetrievalConfirmation(
        ServerKeyRetrievalRequest storage request,
        uint8 authorityIndex,
        bytes32 confirmation,
        uint256 threshold) private returns (ConfirmationSupport)
    {
        // insert threshold confirmation
        bytes32 thresholdConfirmation = bytes32(threshold);
        ConfirmationSupport thresholdConfirmationSupport = insertConfirmation(request.thresholdConfirmations,
            authorityIndex, addresses.length / 2, thresholdConfirmation);
        if (thresholdConfirmationSupport == ConfirmationSupport.Impossible) {
            return thresholdConfirmationSupport;
        }

        // insert confirmation itself
        bool checkThreshold = (thresholdConfirmationSupport == ConfirmationSupport.Confirmed);
        ConfirmationSupport confirmationSupport = insertConfirmation(request.confirmations, authorityIndex,
            threshold, confirmation);
        if (!checkThreshold && confirmationSupport == ConfirmationSupport.Impossible) {
            return ConfirmationSupport.Unconfirmed;
        }
        return confirmationSupport;
    }

    /// Delete server key retrieval request.
    function deleteServerKeyRetrievalRequest(bytes32 serverKeyId, ServerKeyRetrievalRequest storage request) private {
        clearConfirmations(request.confirmations);
        clearConfirmations(request.thresholdConfirmations);
        delete serverKeyRetrievalRequests[serverKeyId];

        removeRequestKey(serverKeyRetrievalRequestsKeys, serverKeyId);
    }

    /// Pending generation requests.
    mapping (bytes32 => ServerKeyRetrievalRequest) serverKeyRetrievalRequests;
    /// Pending generation requests keys.
    bytes32[] serverKeyRetrievalRequestsKeys;
}


/// Document key store service contract. This contract allows to store externally generated document key, which
/// could be retrieved later.
contract DocumentKeyStoreService is AuthoritiesOwned {
    /// Document key store fee.
    uint256 constant DKS_FEE = 100 finney;
    /// Maximal number of active document key store requests. We're limiting this number to avoid
    /// infinite gas costs of some functions.
    uint256 constant DKS_MAX_REQUESTS = 16;

    /// Document key store request.
    struct DocumentKeyStoreRequest {
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

    /// Request document key store.
    function storeDocumentKey(bytes32 serverKeyId, bytes commonPoint, bytes encryptedPoint) public payable
        whenFeePaid(DKS_FEE)
        validPublic(commonPoint)
        validPublic(encryptedPoint)
    {
        // check maximum number of requests
        require(documentKeyStoreRequestsKeys.length < DKS_MAX_REQUESTS);

        DocumentKeyStoreRequest storage request = documentKeyStoreRequests[serverKeyId];
        require(request.author == address(0));
        deposit(msg.value);

        request.author = msg.sender;
        request.commonPoint = commonPoint;
        request.encryptedPoint = encryptedPoint;
        documentKeyStoreRequestsKeys.push(serverKeyId);

        DocumentKeyStoreRequested(serverKeyId, msg.sender, commonPoint, encryptedPoint);
    }

    /// Called when store is reported by one of authorities.
    function documentKeyStored(bytes32 serverKeyId) public {
        // check that it is called by authority
        uint8 authorityIndex = requireAuthority(msg.sender);

        // check if request still active
        DocumentKeyStoreRequest storage request = documentKeyStoreRequests[serverKeyId];
        if (request.author == address(0)) {
            return;
        }

        // insert confirmation (we're waiting for confirmations from all authorities here)
        bytes32 confirmation = bytes32(0);
        ConfirmationSupport confirmationSupport = insertConfirmation(request.confirmations, authorityIndex,
            addresses.length - 1, confirmation);

        // ...and check if there are enough confirmations
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
    function documentKeyStoreError(bytes32 serverKeyId) public {
        // check that it is called by authority
        requireAuthority(msg.sender);

        // check if request still active
        DocumentKeyStoreRequest storage request = documentKeyStoreRequests[serverKeyId];
        if (request.author == address(0)) {
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
        bytes32 serverKeyId = documentKeyStoreRequestsKeys[index];
        DocumentKeyStoreRequest storage request = documentKeyStoreRequests[serverKeyId];
        return (
            serverKeyId,
            request.author,
            request.commonPoint,
            request.encryptedPoint
        );
    }

    /// Get document key store request confirmation status.
    function getDocumentKeyStoreRequestConfirmationStatus(bytes32 serverKeyId, address authority) view public returns (bool) {
        uint8 authorityIndex = requireAuthority(authority);
        DocumentKeyStoreRequest storage request = documentKeyStoreRequests[serverKeyId];
        return !isConfirmedByAuthority(request.confirmations, authorityIndex);
    }

    /// Delete document key store request.
    function deleteDocumentKeyStoreRequest(bytes32 serverKeyId, DocumentKeyStoreRequest storage request) private {
        clearConfirmations(request.confirmations);
        delete documentKeyStoreRequests[serverKeyId];

        removeRequestKey(documentKeyStoreRequestsKeys, serverKeyId);
    }

    /// Pending store requests.
    mapping (bytes32 => DocumentKeyStoreRequest) documentKeyStoreRequests;
    /// Pending store requests keys.
    bytes32[] documentKeyStoreRequestsKeys;
}

/// Document key retrieval service contract. This contract allows to retrieve previously stored document key.
contract DocumentKeyShadowRetrievalService is AuthoritiesOwned {
    /// Document key retrieval fee.
    uint256 constant DKSSR_FEE = 100 finney;
    /// Maximal number of active document key shadow retrieval requests. We're limiting this number to avoid
    /// infinite gas costs of some functions.
    uint256 constant DKSSR_MAX_REQUESTS = 16;

    /// Document key shadow retrieval request.
    struct DocumentKeyShadowRetrievalRequest {
        bytes32 serverKeyId;
        bytes requesterPublic;
        Confirmations thresholdConfirmations;
        bool isCommonRetrievalCompleted;
        uint256 threshold;
        uint256 personalRetrievalErrors;
        uint8 personalRetrievalErrorsCount;
        bytes32[] dataKeys;
        mapping (bytes32 => DocumentKeyShadowRetrievalData) data;
    }

    /// Document key retrieval data.
    struct DocumentKeyShadowRetrievalData {
        uint256 participants;
        uint256 reported;
        uint8 reportedCount;
    }

    /// When document key common-portion retrieval request is received.
    event DocumentKeyCommonRetrievalRequested(bytes32 serverKeyId, address requester);
    /// When document key common portion is retrieved.
    event DocumentKeyCommonRetrieved(bytes32 indexed serverKeyId, address indexed requester, bytes commonPoint, uint256 threshold);
    /// When document key personal portion is retrieved.
    event DocumentKeyPersonalRetrieved(bytes32 indexed serverKeyId, address indexed requester, bytes decryptedSecret, bytes shadow);
    /// When error occurs during document key retrieval.
    event DocumentKeyShadowRetrievalError(bytes32 indexed serverKeyId, address indexed requester);

    /// Request document key retrieval.
    function retrieveDocumentKeyShadow(bytes32 serverKeyId, bytes requesterPublic) public payable
        whenFeePaid(DKSSR_FEE)
        validPublic(requesterPublic)
    {
        // we only accept requests from owner of requesterPublic key
        require(address(uint(keccak256(requesterPublic)) & 0x00FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF) == msg.sender);
        // check maximum number of requests
        require(documentKeyShadowRetrievalRequestsKeys.length < DKSSR_MAX_REQUESTS);

        bytes32 retrievalId = keccak256(serverKeyId, msg.sender);
        DocumentKeyShadowRetrievalRequest storage request = documentKeyShadowRetrievalRequests[retrievalId];
        require(request.requesterPublic.length == 0);
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

        request.serverKeyId = serverKeyId;
        request.requesterPublic = requesterPublic;
        documentKeyShadowRetrievalRequestsKeys.push(retrievalId);

        DocumentKeyCommonRetrievalRequested(serverKeyId, msg.sender);
    }

    /// Called when common data is reported by one of authorities.
    function documentKeyCommonRetrieved(bytes32 serverKeyId, address requester, bytes commonPoint, uint256 threshold) public validPublic(commonPoint) {
        // check that it is called by authority
        uint8 authorityIndex = requireAuthority(msg.sender);

        // check if request still active
        bytes32 retrievalId = keccak256(serverKeyId, requester);
        DocumentKeyShadowRetrievalRequest storage request = documentKeyShadowRetrievalRequests[serverKeyId];
        if (request.requesterPublic.length == 0 || request.isCommonRetrievalCompleted) {
            return;
        }

        // insert confirmation
        bytes32 thresholdConfirmation = keccak256(commonPoint, threshold);
        ConfirmationSupport thresholdConfirmationSupport = insertConfirmation(request.thresholdConfirmations, authorityIndex,
            addresses.length / 2, thresholdConfirmation);

        // ...and check if there are enough confirmations
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

        // ...and publish common data (this is also a signal to 'master' key server to start decryption)
        DocumentKeyCommonRetrieved(serverKeyId, requester, commonPoint, threshold);
    }

    /// Called when 'personal' data is reported by one of authorities.
    function documentKeyPersonalRetrieved(bytes32 serverKeyId, address requester, uint256 participants, bytes decryptedSecret, bytes shadow) public
        validPublic(decryptedSecret)
    {
        // check that it is called by authority
        uint8 authorityIndex = requireAuthority(msg.sender);

        // check if request still active
        bytes32 retrievalId = keccak256(serverKeyId, requester);
        DocumentKeyShadowRetrievalRequest storage request = documentKeyShadowRetrievalRequests[retrievalId];
        if (request.requesterPublic.length == 0) {
            return;
        }
        require(request.isCommonRetrievalCompleted);

        // there must be exactly threshold + 1 participants
        // require(request.threshold + 1 == participants.length);

        // authority must have an entry in participants
        uint256 authorityMask = (uint256(1) << authorityIndex);
        require((participants & authorityMask) != 0);

        // insert new data
        bytes32 retrievalDataId = keccak256(participants, decryptedSecret);
        DocumentKeyShadowRetrievalData storage data = request.data[retrievalDataId];
        if (data.participants == 0) {
            request.dataKeys.push(retrievalDataId);
            data.participants = participants;
        } else {
            require((data.reported & authorityMask) == 0);
        }

        // remember result
        data.reportedCount += 1;
        data.reported |= authorityMask;

        // publish personal portion
        DocumentKeyPersonalRetrieved(serverKeyId, requester, decryptedSecret, shadow);

        // check if all participants have responded
        if (request.threshold + 1 != data.reportedCount) {
            return;
        }

        // delete request and publish key
        deleteDocumentKeyShadowRetrievalRequest(retrievalId, request);
        return;
    }

    /// Called when error occurs during document key retrieval.
    function documentKeyShadowRetrievalError(bytes32 serverKeyId, address requester) public {
        // check that it is called by authority
        uint8 authorityIndex = requireAuthority(msg.sender);

        // check if request still active
        bytes32 retrievalId = keccak256(serverKeyId, requester);
        DocumentKeyShadowRetrievalRequest storage request = documentKeyShadowRetrievalRequests[retrievalId];
        if (request.requesterPublic.length == 0) {
            return;
        }

        // error on common data retrieval step is treated like a voting for non-existant common data
        if (!request.isCommonRetrievalCompleted) {
            // insert confirmation
            bytes32 thresholdConfirmation = bytes32(0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF);
            ConfirmationSupport thresholdConfirmationSupport = insertConfirmation(request.thresholdConfirmations, authorityIndex,
                addresses.length / 2, thresholdConfirmation);

            // ...and check if there are enough confirmations
            if (thresholdConfirmationSupport == ConfirmationSupport.Unconfirmed) {
                return;
            }

            // delete request and fire event
            deleteDocumentKeyShadowRetrievalRequest(retrievalId, request);
            DocumentKeyShadowRetrievalError(serverKeyId, requester);
            return;
        }

        // when error occurs on personal retrieval step, we're waiting until there are threshold + 1 errors
        // check if haven't voted before
        uint256 authorityMask = uint256(1) << authorityIndex;
        if ((request.personalRetrievalErrors & authorityMask) != 0) {
            return;
        }
        request.personalRetrievalErrors |= authorityMask;
        request.personalRetrievalErrorsCount += 1;

        // check if we have enough errors
        if (request.threshold + 1 != request.personalRetrievalErrorsCount) {
            return;
        }

        // delete request and fire event
        deleteDocumentKeyShadowRetrievalRequest(retrievalId, request);
        DocumentKeyShadowRetrievalError(serverKeyId, requester);
        return;
    }

    /// Get count of pending document key retrieval requests.
    function documentKeyShadowRetrievalRequestsCount() view public returns (uint) {
        return documentKeyShadowRetrievalRequestsKeys.length;
    }

    /// Get document key retrieval request with given index.
    /// Returns: (serverKeyId, requesterPublic, isCommonRetrievalCompleted)
    function getDocumentKeyShadowRetrievalRequest(uint index) view public returns (bytes32, bytes, bool) {
        bytes32 retrievalId = documentKeyShadowRetrievalRequestsKeys[index];
        DocumentKeyShadowRetrievalRequest storage request = documentKeyShadowRetrievalRequests[retrievalId];
        return (
            request.serverKeyId,
            request.requesterPublic,
            request.isCommonRetrievalCompleted
        );
    }

    /// Get document key store request confirmation status.
    function getDocumentKeyShadowRetrievalRequestConfirmationStatus(bytes32 serverKeyId, address requester, address authority) view public returns (bool) {
        uint8 authorityIndex = requireAuthority(authority);
        bytes32 retrievalId = keccak256(serverKeyId, requester);
        DocumentKeyShadowRetrievalRequest storage request = documentKeyShadowRetrievalRequests[retrievalId];
        return !request.isCommonRetrievalCompleted &&
            !isConfirmedByAuthority(request.thresholdConfirmations, authorityIndex);
    }

    /// Delete document key retrieval request.
    function deleteDocumentKeyShadowRetrievalRequest(bytes32 retrievalId, DocumentKeyShadowRetrievalRequest storage request) private {
        for (uint i = 0; i < request.dataKeys.length; ++i) {
            delete request.data[request.dataKeys[i]];
        }
        clearConfirmations(request.thresholdConfirmations);
        delete documentKeyShadowRetrievalRequests[retrievalId];

        removeRequestKey(documentKeyShadowRetrievalRequestsKeys, retrievalId);
    }

    /// Pending retrieval requests.
    mapping (bytes32 => DocumentKeyShadowRetrievalRequest) documentKeyShadowRetrievalRequests;
    /// Pending retrieval requests keys.
    bytes32[] documentKeyShadowRetrievalRequestsKeys;
}

/// Secret store service contract.
contract SecretStoreService is AuthoritiesOwned, ServerKeyGenerationService,
    ServerKeyRetrievalService, DocumentKeyStoreService, DocumentKeyShadowRetrievalService {
    /// Constructor.
    function SecretStoreService(address[] initialAuthorities) AuthoritiesOwned(initialAuthorities) public {
    }
}
