// WalletLibrary contract, by Nicolas Gotchac.
// Copyright Parity Technologies Ltd (UK), 2016.
// This code may be distributed under the terms of the Apache Licence, version 2
// or the MIT Licence, at your choice.

pragma solidity ^0.4.11;

contract Wallet {
    function Wallet(address[] _owners, uint _required, uint _daylimit) {
        // Signature of the Wallet Library's init function
        bytes4 sig = bytes4(sha3("init_wallet(address[],uint256,uint256)"));

        // Compute the size of the call data : arrays has 2
        // 32bytes for offset and length, plus 32bytes per element ;
        // plus 2 32bytes for each uint
        uint argarraysize = (2 + _owners.length);
        uint argsize = (2 + argarraysize) * 32;

        // total data size:
        //   4 bytes for the signature + the arguments size
        uint size = 4 + argsize;
        bytes32 m_data = _malloc(size);

        // copy the signature and arguments data to the
        // data pointer
        assembly {
            // Add the signature first to memory
            mstore(m_data, sig)
            // Add the call data, which is at the end of the code
            codecopy(add(m_data, 0x4), sub(codesize, argsize), argsize)
        }

        // execute the call (to initWallet)
        _call(m_data, size);
    }

    // delegate any contract calls to
    // the library
    function() payable {
        uint size = msg.data.length;
        bytes32 m_data = _malloc(size);

        assembly {
            calldatacopy(m_data, 0x0, size)
        }

        bytes32 m_result = _call(m_data, size);

        assembly {
            return(m_result, 0x20)
        }
    }

    // allocate the given size in memory and return
    // the pointer
    function _malloc(uint size) private returns(bytes32) {
        bytes32 m_data;

        assembly {
            // Get free memory pointer and update it
            m_data := mload(0x40)
            mstore(0x40, add(m_data, size))
        }

        return m_data;
    }

    // make a delegatecall to the target contract, given the
    // data located at m_data, that has the given size
    //
    // @returns A pointer to memory which contain the 32 first bytes
    //          of the delegatecall output
    function _call(bytes32 m_data, uint size) private returns(bytes32) {
        address target = 0x492934308E98b590A626666B703A6dDf2120e85e;
        bytes32 m_result = _malloc(32);

        assembly {
            let failed := iszero(delegatecall(sub(gas, 10000), target, m_data, size, m_result, 0x20))

            jumpi(exception, failed)
            jump(exit)

        exception:
            invalid

        exit:
        }

        return m_result;
    }
}
