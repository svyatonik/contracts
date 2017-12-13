//! The KeyServerSet contract.
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

// Simple key server set.
interface KeyServerSet {
	// Get all current key servers.
	function getCurrentKeyServers() public constant returns (address[]);
	// Get current key server public key.
	function getCurrentKeyServerPublic(address keyServer) public constant returns (bytes);
	// Get current key server address.
	function getCurrentKeyServerAddress(address keyServer) public constant returns (string);
}

// Key server set with migration support.
interface KeyServerSetWithMigration {
	// When new server is added to new set.
	event KeyServerAdded(address keyServer);
	// When existing server is removed from new set.
	event KeyServerRemoved(address keyServer);
	// When migration is started.
	event MigrationStarted();
	// When migration is completed.
	event MigrationCompleted();

	// Get all current key servers.
	function getCurrentKeyServers() public constant returns (address[]);
	// Get current key server public key.
	function getCurrentKeyServerPublic(address keyServer) public constant returns (bytes);
	// Get current key server address.
	function getCurrentKeyServerAddress(address keyServer) public constant returns (string);

	// Get all migration key servers.
	function getMigrationKeyServers() public constant returns (address[]);
	// Get migration key server public key.
	function getMigrationKeyServerPublic(address keyServer) public constant returns (bytes);
	// Get migration key server address.
	function getMigrationKeyServerAddress(address keyServer) public constant returns (string);

	// Get all new key servers.
	function getNewKeyServers() public constant returns (address[]);
	// Get new key server public key.
	function getNewKeyServerPublic(address keyServer) public constant returns (bytes);
	// Get new key server address.
	function getNewKeyServerAddress(address keyServer) public constant returns (string);

	// Get migration id.
	function getMigrationId() public view returns (bytes32);
	// Get migration master.
	function getMigrationMaster() public constant returns (address);
	// Is migration confirmed by given node?
	function isMigrationConfirmed(address keyServer) public view returns (bool);
	// Start migration.
	function startMigration(bytes32 id) public;
	// Confirm migration.
	function confirmMigration(bytes32 id) public;
}
