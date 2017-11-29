//! The prism ETH/ETC split contract.
//!
//! Copyright 2016 Gavin Wood, Parity Technologies Ltd.
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

pragma solidity ^0.4.6;

contract Prism {
	address constant theWithdraw = 0xbf4ed7b27f1d666546e30d74d50d173d20bca754;
	function Prism() {
		forked = theWithdraw.balance > 1 ether;
	}

	function transferETC(address to) payable {
		if (forked)
			throw;
		if (!to.send(msg.value))
			throw;
	}

	function transferETH(address to) payable {
		if (!forked)
			throw;
		if (!to.send(msg.value))
			throw;
	}

	bool public forked;
}
