//sol CoreVeto
// Asymmetric, dual-sig wallet.
// @authors:
// Gav Wood <gavin@parity.io>
// Two predefined and constant accounts are symbiotic; owner may submit transactions for
// execution and some pre-defined period later, may have them be executed.
// Within this period either of the two accounts may cancel the request for
// some predefined (anti-griefing) value to be paid.
// Designed to be used with other, more complex, account access infrastructure
// as a final fail-safe mechanism to ensure the chances of outright theft are
// minimised.
// Currently there is no functionality to alter the identities of these two
// accounts, mainly to reduce complexity and ensure the logic is bug-free.
contract CoreVeto {
	function CoreVeto(address _owner, address _veto, uint _vetoPayment, uint _vetoPeriod) {
		owner = _owner;
		veto = _veto;
		vetoPayment = _vetoPayment;
		vetoPeriod = _vetoPeriod;
	}

	function permit(bytes32 _txHash) only_owner {
		requests[_txHash] = now + vetoPeriod;
	}

	function execute(address _to, uint _value, bytes _data) only_permitted(sha3(msg.data)) {
		require(_to.call.value(_value)(_data));
		delete requests[sha3(msg.data)];
	}

	function veto(bytes32 _txHash) payable only_vetoer only_paid {
		delete requests[_txHash];
	}

	function () payable {}

	modifier only_permitted(bytes32 txHash) { require(requests[txHash] != 0 && now > requests[txHash]); _; }
	modifier only_vetoer { require(msg.sender == veto || msg.sender == owner); _; }
	modifier only_owner { require(msg.sender == owner); _; }
	modifier only_paid { require(msg.value >= vetoPayment); _; }

	// Constants
	address public owner;
	address public veto;
	uint public vetoPayment;
	uint public vetoPeriod;

	// State
	mapping (bytes32 => uint) public requests;
}
