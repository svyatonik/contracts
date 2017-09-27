//! Timed deposit contract.
//! By Gavin Wood, 2017.
//! Released under the Apache Licence 2.

pragma solidity ^0.4.17;

/// Simple deposit contract. Effectively a single-use 1 of 2, except that one
/// (the sender) cannot access the funds until after 6 months.
contract TimedDeposit {
	function TimedDeposit(address _receiver) public {
		receiver = _receiver;
		expiry = now + 6 * 30 days;
	}

	function () public payable {
	    require(msg.sender == sender || sender == 0);
        sender = msg.sender;
	}

	function refund() public {
		require(msg.sender == sender);
		require(now > expiry);
		selfdestruct(sender);
	}

	function take() public {
		require(msg.sender == receiver);
		selfdestruct(receiver);
	}

	address public sender;
	address public receiver;
	uint public expiry;
}
