pragma solidity ^0.4.6;

import "Owned.sol";

contract KeyServerSet is Owned {
	struct KeyServer {
		// Index in the keyServersList.
		uint index;
		// Public key of key server.
		bytes publicKey;
		// IP address of key server.
		string ip;
	}

	// Public keys of all active key servers.
	address[] public keyServersList;
	// Mapping public key => server IP address.
	mapping(address => KeyServer) keyServers;

	// When new server is added to set.
	event KeyServerAdded(address keyServer);
	// When existing server is removed from set.
	event KeyServerRemoved(address keyServer);

	// Only if valid public is passed
	modifier valid_public(bytes keyServerPublic) { require(keyServerPublic.length == 64); _; }
	// Only run if server is not currently in the set.
	modifier new_key_server(address keyServer) { require(sha3(keyServers[keyServer].ip) == sha3("")); _; }
	// Only run if server is currently in the set.
	modifier old_key_server(address keyServer) { require(sha3(keyServers[keyServer].ip) != sha3("")); _; }

	// Get all active key servers public keys.
	function getKeyServers() constant returns (address[]) {
		return keyServersList;
	}

	// Get key server public key.
	function getKeyServerPublic(address keyServer) old_key_server(keyServer) constant returns (bytes) {
		return keyServers[keyServer].publicKey;
	}

	// Get key server address.
	function getKeyServerAddress(address keyServer) old_key_server(keyServer) constant returns (string) {
		return keyServers[keyServer].ip;
	}
 
	// Add new key server to set.
	function addKeyServer(bytes keyServerPublic, string keyServerIp) public only_owner valid_public(keyServerPublic) new_key_server(computeAddress(keyServerPublic)) {
		// compute address from public
		address keyServer = computeAddress(keyServerPublic);
		// fire event
		KeyServerAdded(keyServer);
		// append to the list and to the map
		keyServers[keyServer].index = keyServersList.length;
		keyServers[keyServer].publicKey = keyServerPublic;
		keyServers[keyServer].ip = keyServerIp;
		keyServersList.push(keyServer);
	}

	// Remove key server from set.
	function removeKeyServer(address keyServer) public only_owner old_key_server(keyServer) {
		// fire event
		KeyServerRemoved(keyServer);
		// swap list elements (removedIndex, lastIndex)
		uint removedIndex = keyServers[keyServer].index;
		uint lastIndex = keyServersList.length - 1;
		address lastKeyServer = keyServersList[lastIndex];
		keyServersList[removedIndex] = lastKeyServer;
		keyServers[lastKeyServer].index = removedIndex;
		// remove element from list and map
		delete keyServersList[lastIndex];
		delete keyServers[keyServer];
		keyServersList.length--;
	}

	// Compute address from public key.
	function computeAddress(bytes keyServerPublic) constant private returns (address) {
		return address(uint(keccak256(keyServerPublic)) & 0x00FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF);
	}
}
