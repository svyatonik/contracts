//! The Secret Store server key retrieval service contract.
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

pragma solidity ^0.4.21;

import "./interfaces/SecretStoreService.sol";
import "./SecretStoreServiceBase.sol";


/// Server Key retrieval service contract.
contract SecretStoreServerKeyRetrievalService is SecretStoreServiceBase,
    ServerKeyRetrievalServiceClientApi, ServerKeyRetrievalServiceKeyServerApi {
    /// Server key retrieval request.
    struct ServerKeyRetrievalRequest {
        bool isActive;
        RequestResponses thresholdResponses;
        RequestResponses responses;
    }

    /// When sever key retrieval request is received.
    event ServerKeyRetrievalRequested(bytes32 serverKeyId);
    /// When server key is retrieved.
    event ServerKeyRetrieved(bytes32 indexed serverKeyId, bytes serverKeyPublic);
    /// When error occurs during server key retrieval.
    event ServerKeyRetrievalError(bytes32 indexed serverKeyId);

    /// Constructor.
    function SecretStoreServerKeyRetrievalService(address keyServerSetAddressInit) SecretStoreServiceBase(keyServerSetAddressInit) public {
        serverKeyRetrievalFee = 100 finney;
        maxServerKeyRetrievalRequests = 8;
    }

    // === Administrative methods ===

    /// Set server key retrieval fee.
    function setServerKeyRetrievalFee(uint256 newFee) public only_owner {
        serverKeyRetrievalFee = newFee;
    }

    /// Set server key retrieval requests limit.
    function setMaxServerKeyRetrievalRequests(uint256 newLimit) public only_owner {
        maxServerKeyRetrievalRequests = newLimit;
    }

    /// Delete server key retrieval request.
    function deleteServerKeyRetrievalRequest(bytes32 serverKeyId) public only_owner {
        ServerKeyRetrievalRequest storage request = serverKeyRetrievalRequests[serverKeyId];
        clearServerKeyRetrievalRequest(serverKeyId, request);
    }

    // === Interface methods ===

    /// Retrieve existing server key. Retrieved key will be published via ServerKeyRetrieved or ServerKeyRetrievalError.
    function retrieveServerKey(bytes32 serverKeyId) external payable whenFeePaid(serverKeyRetrievalFee) {
        // check maximum number of requests
        require(serverKeyRetrievalRequestsKeys.length < maxServerKeyRetrievalRequests);

        ServerKeyRetrievalRequest storage request = serverKeyRetrievalRequests[serverKeyId];
        require(!request.isActive);
        deposit();

        // we do not know exact threshold value here && we can not blindly trust the first response
        // => we should agree upon two values: threshold && server key itself
        // => assuming that all authorities will eventually respond with value/error, we will wait for:
        // 1) at least 50% + 1 authorities agreement on the same threshold value
        // 2) after threshold is agreed, we will wait for threshold + 1 values of server key

        request.isActive = true;
        serverKeyRetrievalRequestsKeys.push(serverKeyId);

        emit ServerKeyRetrievalRequested(serverKeyId);
    }

    /// Called when retrieval is reported by key server.
    function serverKeyRetrieved(bytes32 serverKeyId, bytes serverKeyPublic, uint8 threshold) external validPublic(serverKeyPublic) {
        // check if request still active
        ServerKeyRetrievalRequest storage request = serverKeyRetrievalRequests[serverKeyId];
        if (!request.isActive) {
            return;
        }

        // insert response (we're waiting for responses from all authorities here)
        // it checks that tx.origin is actually the key server
        uint8 keyServerIndex = requireKeyServer(msg.sender);
        bytes32 response = keccak256(serverKeyPublic);
        ResponseSupport responseSupport = insertServerKeyRetrievalResponse(request, keyServerIndex,
            response, threshold);

        // ...and check if there are enough support
        if (responseSupport == ResponseSupport.Unconfirmed) { // not confirmed (yet)
            return;
        }

        // delete request and fire event
        clearServerKeyRetrievalRequest(serverKeyId, request);
        if (responseSupport == ResponseSupport.Confirmed) { // confirmed
            emit ServerKeyRetrieved(serverKeyId, serverKeyPublic);
        } else { // no consensus possible at all
            emit ServerKeyRetrievalError(serverKeyId);
        }
    }

    /// Called when error occurs during server key retrieval.
    function serverKeyRetrievalError(bytes32 serverKeyId) external {
        // check if request still active
        ServerKeyRetrievalRequest storage request = serverKeyRetrievalRequests[serverKeyId];
        if (!request.isActive) {
            return;
        }

        // check that it is called by key server
        uint8 keyServerIndex = requireKeyServer(msg.sender);

        // all key servers in SS with auto-migration enabled should have a share for every key
        // => we could make an error fatal, but let's tolerate such issues
        // => insert invalid response and check if there are enough confirmations
        bytes32 invalidResponse = bytes32(0);
        ResponseSupport responseSupport = insertServerKeyRetrievalResponse(request, keyServerIndex,
            invalidResponse, keyServersCount() / 2);
        if (responseSupport == ResponseSupport.Unconfirmed) {
            return;
        }

        // delete request and fire event
        clearServerKeyRetrievalRequest(serverKeyId, request);
        emit ServerKeyRetrievalError(serverKeyId);
    }

    /// Get count of pending server key retrieval requests.
    function serverKeyRetrievalRequestsCount() view external returns (uint256) {
        return serverKeyRetrievalRequestsKeys.length;
    }

    /// Get server key retrieval request with given index.
    /// Returns: (serverKeyId)
    function getServerKeyRetrievalRequest(uint256 index) view external returns (bytes32) {
        bytes32 serverKeyId = serverKeyRetrievalRequestsKeys[index];
        return (
            serverKeyId,
        );
    }

    /// Returs true if response from given keyServer is required.
    function isServerKeyRetrievalResponseRequired(bytes32 serverKeyId, address keyServer) view external returns (bool) {
        uint8 keyServerIndex = requireKeyServer(keyServer);
        ServerKeyRetrievalRequest storage request = serverKeyRetrievalRequests[serverKeyId];
        return isResponseRequired(request.thresholdResponses, keyServerIndex);
    }

    /// Insert both threshold and public response.
    function insertServerKeyRetrievalResponse(
        ServerKeyRetrievalRequest storage request,
        uint8 keyServerIndex,
        bytes32 response,
        uint8 threshold) private returns (ResponseSupport)
    {
        // insert threshold response
        bytes32 thresholdResponse = bytes32(threshold);
        ResponseSupport thresholdResponseSupport = insertResponse(request.thresholdResponses, keyServerIndex,
            keyServersCount() / 2, thresholdResponse);
        if (thresholdResponseSupport == ResponseSupport.Impossible) {
            return thresholdResponseSupport;
        }

        // insert response itself
        bool checkThreshold = (thresholdResponseSupport == ResponseSupport.Confirmed);
        ResponseSupport responseSupport = insertResponse(request.responses, keyServerIndex,
            threshold, response);
        if (!checkThreshold && responseSupport == ResponseSupport.Impossible) {
            return ResponseSupport.Unconfirmed;
        }
        return responseSupport;
    }

    /// Clear server key retrieval request traces.
    function clearServerKeyRetrievalRequest(bytes32 serverKeyId, ServerKeyRetrievalRequest storage request) private {
        clearResponses(request.responses);
        delete serverKeyRetrievalRequests[serverKeyId];

        removeRequestKey(serverKeyRetrievalRequestsKeys, serverKeyId);
    }

    /// Server key retrieval fee.
    uint256 public serverKeyRetrievalFee;
    /// Maximal number of active server key retrieval requests. We're limiting this number to avoid
    /// infinite gas costs of some functions.
    uint256 public maxServerKeyRetrievalRequests;

    /// Pending retrieval requests.
    mapping (bytes32 => ServerKeyRetrievalRequest) private serverKeyRetrievalRequests;
    /// Pending retrieval requests keys.
    bytes32[] private serverKeyRetrievalRequestsKeys;
}
