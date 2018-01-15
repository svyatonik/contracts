//! The KeyServerSet contract. Owned version with migration support.
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

import "../Owned.sol";
import "./interfaces/KeyServerSet.sol";


// Single-owned KeyServerSet with migration support.
contract OwnedKeyServerSetWithMigration is Owned, KeyServerSetWithMigration {
    struct KeyServer {
        // Index in the keyServersList.
        uint index;
        // Public key of key server.
        bytes publicKey;
        // IP address of key server.
        string ip;
    }

    struct Set {
        // Public keys of all active key servers.
        address[] list;
        // Mapping public key => server IP address.
        mapping(address => KeyServer) map;
    }

    // When new server is added to new set.
    event KeyServerAdded(address keyServer);
    // When existing server is removed from new set.
    event KeyServerRemoved(address keyServer);
    // When migration is started.
    event MigrationStarted();
    // When migration is completed.
    event MigrationCompleted();

    // Is initialized.
    bool isInitialized;
    // Current key servers set.
    Set currentSet;
    // Migration key servers set.
    Set migrationSet;
    // New key servers set.
    Set newSet;
    // Migration master.
    address migrationMaster;
    // Migration id.
    bytes32 migrationId;
    // Required migration confirmations.
    mapping(address => bool) migrationConfirmations;

    // Only if valid public is passed
    modifier isValidPublic(bytes keyServerPublic) {
        require(checkPublic(keyServerPublic));
        _;
    }

    // Only run if server is currently on current set.
    modifier isOnCurrentSet(address keyServer) {
        require(keccak256(currentSet.map[keyServer].ip) != keccak256(""));
        _;
    }

    // Only run if server is currently on migration set.
    modifier isOnMigrationSet(address keyServer) {
        require(keccak256(migrationSet.map[keyServer].ip) != keccak256(""));
        _;
    }

    // Only run if server is currently on new set.
    modifier isOnNewSet(address keyServer) {
        require(keccak256(newSet.map[keyServer].ip) != keccak256(""));
        _;
    }

    // Only run if server is currently on new set.
    modifier isNotOnNewSet(address keyServer) {
        require(keccak256(newSet.map[keyServer].ip) == keccak256(""));
        _;
    }

    // Only when no active migration process.
    modifier noActiveMigration {
        require(migrationMaster == address(0));
        _;
    }

    // Only when migration with given id is in progress.
    modifier isActiveMigration(bytes32 id) {
        require(migrationId == id);
        _;
    }

    // Only when migration id is valid.
    modifier isValidMigrationId(bytes32 id) {
        require(id != bytes32(0));
        _;
    }

    // Only when migration is required.
    modifier whenMigrationRequired {
        require(!areEqualSets(currentSet, newSet));
        _;
    }

    // Only run when sender is potential participant of migration.
    modifier isPossibleMigrationParticipant {
        require(
            keccak256(currentSet.map[msg.sender].ip) != keccak256("") ||
            keccak256(newSet.map[msg.sender].ip) != keccak256(""));
        _;
    }

    // Only run when sender is participant of migration.
    modifier isMigrationParticipant(address keyServer) {
        require(
            keccak256(currentSet.map[keyServer].ip) != keccak256("") ||
            keccak256(migrationSet.map[keyServer].ip) != keccak256(""));
        _;
    }

    // Complete initialization. Before this function is called, all calls to addKeyServer/removeKeyServer
    // affect both newSet and currentSet.
    function completeInitialization() public only_owner {
        require(!isInitialized);
        isInitialized = true;
    }

    // Get all current key servers.
    function getCurrentKeyServers() public constant returns (address[]) {
        return currentSet.list;
    }

    // Get current key server public key.
    function getCurrentKeyServerPublic(address keyServer) isOnCurrentSet(keyServer) public constant returns (bytes) {
        return currentSet.map[keyServer].publicKey;
    }

    // Get current key server address.
    function getCurrentKeyServerAddress(address keyServer) isOnCurrentSet(keyServer) public constant returns (string) {
        return currentSet.map[keyServer].ip;
    }

    // Get all migration key servers.
    function getMigrationKeyServers() public constant returns (address[]) {
        return migrationSet.list;
    }

    // Get migration key server public key.
    function getMigrationKeyServerPublic(address keyServer) isOnMigrationSet(keyServer) public constant returns (bytes) {
        return migrationSet.map[keyServer].publicKey;
    }

    // Get migration key server address.
    function getMigrationKeyServerAddress(address keyServer) isOnMigrationSet(keyServer) public constant returns (string) {
        return migrationSet.map[keyServer].ip;
    }

    // Get all new key servers.
    function getNewKeyServers() public constant returns (address[]) {
        return newSet.list;
    }

    // Get new key server public key.
    function getNewKeyServerPublic(address keyServer) isOnNewSet(keyServer) public constant returns (bytes) {
        return newSet.map[keyServer].publicKey;
    }

    // Get new key server address.
    function getNewKeyServerAddress(address keyServer) isOnNewSet(keyServer) public constant returns (string) {
        return newSet.map[keyServer].ip;
    }

    // Add new key server to set.
    function addKeyServer(bytes keyServerPublic, string keyServerIp) public only_owner isValidPublic(keyServerPublic) isNotOnNewSet(computeAddress(keyServerPublic)) {
        // append to the new set
        address keyServer = appendToSet(newSet, keyServerPublic, keyServerIp);
        // also append to current set
        if (!isInitialized) {
            appendToSet(currentSet, keyServerPublic, keyServerIp);
        }
        // fire event
        KeyServerAdded(keyServer);
    }

    // Remove key server from set.
    function removeKeyServer(address keyServer) public only_owner isOnNewSet(keyServer) {
        // remove element from the new set
        removeFromSet(newSet, keyServer);
        // also remove from the current set
        if (!isInitialized) {
            removeFromSet(currentSet, keyServer);
        }
        // fire event
        KeyServerRemoved(keyServer);
    }

    // Get migration id.
    function getMigrationId() isValidMigrationId(migrationId) public view returns (bytes32) {
        return migrationId;
    }

    // Start migration.
    function startMigration(bytes32 id) public noActiveMigration isValidMigrationId(id) whenMigrationRequired isPossibleMigrationParticipant {
        // migration to empty set is impossible
        require (newSet.list.length != 0);

        migrationMaster = msg.sender;
        migrationId = id;
        copySet(migrationSet, newSet);
        MigrationStarted();
    }

    // Confirm migration.
    function confirmMigration(bytes32 id) public isValidMigrationId(id) isActiveMigration(id) isOnMigrationSet(msg.sender) {
        require(!migrationConfirmations[msg.sender]);
        migrationConfirmations[msg.sender] = true;

        // check if migration is completed
        for (uint j = 0; j < migrationSet.list.length; ++j) {
            if (!migrationConfirmations[migrationSet.list[j]]) {
                return;
            }
        }

        // migration is completed => delete confirmations
        for (uint m = 0; m < migrationSet.list.length; ++m) {
            delete migrationConfirmations[migrationSet.list[m]];
        }
        delete migrationMaster;

        // ...and copy migration set to current set
        copySet(currentSet, migrationSet);

        // ...and also delete entries from migration set
        clearSet(migrationSet);

        // ...and fire completion event
        MigrationCompleted();
    }

    // Get migration master.
    function getMigrationMaster() public constant returns (address) {
        return migrationMaster;
    }

    // Is migration confirmed.
    function isMigrationConfirmed(address keyServer) public view isMigrationParticipant(keyServer) returns (bool) {
        return migrationConfirmations[keyServer];
    }

    // Compute address from public key.
    function computeAddress(bytes keyServerPublic) private pure returns (address) {
        return address(uint(keccak256(keyServerPublic)) & 0x00FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF);
    }

    // 'Check' public key.
    function checkPublic(bytes keyServerPublic) private pure returns (bool) {
        return keyServerPublic.length == 64;
    }

    // Copy set (assignment operator).
    function copySet(Set storage set1, Set storage set2) private {
        for (uint i = 0; i < set1.list.length; ++i) {
            delete set1.map[set1.list[i]];
        }

        set1.list = set2.list;
        for (uint j = 0; j < set1.list.length; ++j) {
            set1.map[set1.list[j]] = set2.map[set1.list[j]];
        }
    }

    // Clear set.
    function clearSet(Set storage set) private {
        while (set.list.length > 0) {
            var keyServer = set.list[set.list.length - 1];
            delete set.list[set.list.length - 1];
            set.list.length = set.list.length - 1;
            delete set.map[keyServer];
        }
    }

    // Are two sets equal?
    function areEqualSets(Set storage set1, Set storage set2) private view returns (bool) {
        for (uint i = 0; i < set1.list.length; ++i) {
            if (keccak256(set2.map[set1.list[i]].ip) == keccak256("")) {
                return false;
            }
        }
        for (uint j = 0; j < set2.list.length; ++j) {
            if (keccak256(set1.map[set2.list[j]].ip) == keccak256("")) {
                return false;
            }
        }
        return true;
    }

    // Append new key serer to set.
    function appendToSet(Set storage set, bytes keyServerPublic, string keyServerIp) private returns (address) {
        address keyServer = computeAddress(keyServerPublic);
        set.map[keyServer].index = set.list.length;
        set.map[keyServer].publicKey = keyServerPublic;
        set.map[keyServer].ip = keyServerIp;
        set.list.push(keyServer);
        return keyServer;
    }

    // Remove existing key server set.
    function removeFromSet(Set storage set, address keyServer) private {
        // swap list elements (removedIndex, lastIndex)
        uint removedIndex = set.map[keyServer].index;
        uint lastIndex = set.list.length - 1;
        address lastKeyServer = set.list[lastIndex];
        set.list[removedIndex] = lastKeyServer;
        set.map[lastKeyServer].index = removedIndex;
        // remove element from list and map
        delete set.list[lastIndex];
        delete set.map[keyServer];
        set.list.length--;
    }
}
