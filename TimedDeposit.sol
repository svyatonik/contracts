//! The timed deposit contract.
//!
//! Copyright 2017 Gavin Wood, Parity Technologies Ltd.
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
