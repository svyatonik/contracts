pragma solidity ^0.4.18;

/// Authorities-owned contract.
contract AuthoritiesOwned {
	/// Only pass when called by authority.
	modifier onlyAuthority { require (isAuthority(msg.sender)); _; }
	/// Only pass when sender have non-zero balance.
	modifier onlyWithBalance { require (balances[msg.sender] > 0); _; }

	/// Confirmations from authorities.
	struct Confirmations {
		uint threshold;
		mapping (address => bytes32) confirmations;
		address[] confirmedAuthorities;
	}

	/// Constructor.
	function AuthoritiesOwned() internal {
		// change to actual authorities before deployment
		authorities.push(0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF);
	}

	/// Drain balance of sender.
	function drain() public onlyAuthority onlyWithBalance {
		var balance = balances[msg.sender];
		balances[msg.sender] = 0;
		msg.sender.transfer(balance);
	}

	/// Pay equal amount of fee to each of authorities.
	function reinforce(uint amount) internal {
		var authorityShare = amount / authorities.length;
		for (uint i = 0; i < authorities.length - 1; i++) {
			balances[authorities[i]] += authorityShare;
			amount = amount - authorityShare;
		}
		balances[authorities[authorities.length - 1]] += amount;
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
	modifier whenServerKeyGenerationFeePaid { require (msg.value >= serverKeyGenerationFee); _; }
	/// Only pass when 'correct' public is passed.
	modifier validPublicKey(bytes publicKey) { require(publicKey.length == 64); _; }

	/// Generation request.
	struct ServerKeyGenerationRequest {
		bool isActive;
		Confirmations confirmations;
	}

	/// When sever key generation request is received.
	event ServerKeyRequested(bytes32 indexed serverKeyId, uint indexed threshold);
	/// When server key is generated.
	event ServerKeyGenerated(bytes32 indexed serverKeyId, bytes serverKeyPublic);

	/// Request new server key generation.
	/// requester_public must be unique public key (only one key can be generated for given public).
	/// Generated key will be published via ServerKeyGenerated event when available.
	function generateServerKey(bytes32 serverKeyId, uint threshold) public payable whenServerKeyGenerationFeePaid {
		var request = serverKeyGenerationRequests[serverKeyId];
		require(!request.isActive);
		require(threshold + 1 <= getValidatorsCountInternal());
		reinforce(msg.value);
		request.isActive = true;
		request.confirmations.threshold = threshold;
		serverKeyGenerationRequestsKeys.push(serverKeyId);
		ServerKeyRequested(serverKeyId, threshold);
	}

	/// Called when generation is reported by one of key authorities.
	function serverKeyGenerated(bytes32 serverKeyId, bytes serverKeyPublic, uint8 v, bytes32 r, bytes32 s) public validPublicKey(serverKeyPublic) {
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

	/// Get server key generation request with given index.
	function getServerKeyGenerationRequest(address authority, uint index) view public returns (bytes32, uint, bool) {
		require(index < serverKeyGenerationRequestsKeys.length);
		var request = serverKeyGenerationRequests[serverKeyGenerationRequestsKeys[index]];
		require(request.isActive);
		return (serverKeyGenerationRequestsKeys[index],
			request.confirmations.threshold,
			request.confirmations.confirmations[authority] != bytes32(0));
	}

	/// Server key generation fee. TODO: change to actual value
	uint public serverKeyGenerationFee = 1 finney;

	/// Pending generation requests.
	mapping (bytes32 => ServerKeyGenerationRequest) serverKeyGenerationRequests;
	/// Pending requests keys.
	bytes32[] serverKeyGenerationRequestsKeys;
}

/// Secret store service contract.
contract SecretStoreService is ServerKeyGenerator {
}
