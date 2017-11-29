//! The token-calls contract.
//!
//! Copyright 2017 Nicolas Gotchac, Parity Technologies Ltd.
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

/**
 * To use these 2 methods, one must first compile two two contracts
 * (`TokensBalances` and `Tokens`), and extract the bytecode,
 * to which the calldata must be encoded and appended
 * Here is an example of a JS usage:

    const tokensBytecode = '0x...';
    const tokensBalancesBytecode = '0x...';

    const who = [ '0x0000000000000000000000000000000000000000' ];
    const tokenRegAddress = '0x5F0281910Af44bFb5fC7e86A404d0304B0e042F1';
    const tokenStart = 25;
    const tokenLimit = 50;

    function encode (types, values) {
      return api.util.abiEncode(
        null,
        types,
        values
      ).replace('0x', '');
    }

    function decode (type, data) {
      return api.util
        .abiDecode(
          [type] ,
          [
            '0x',
            (32).toString(16).padStart(64, 0),
            data.replace('0x', ''),
          ].join('')
        )
        [0]
        .map((t) => t.value);
    }

    const tokensCalldata = encode(
      ['address', 'uint', 'uint'],
      [tokenRegAddress, tokenStart, tokenLimit]
    );

    let tokens;

    api.eth
      .call({
        data: tokensBytecode + tokensCalldata
      })
      .then((result) => {
        tokens = decode('address[]', result);
      })
      .then(() => {
        const tokensBalancesCallData = encode(
          ['address[]', 'address[]'],
          [who, tokens]
        );

        return api.eth.call({ data: tokensBalancesBytecode + tokensBalancesCallData });
      })
      .then((result) => {
        const rawBalances = decode('uint[]', result);
        const balances = {};

        who.forEach((address, whoIndex) => {
          balances[address] = {};

          tokens.forEach((token, tokenIndex) => {
            const index = whoIndex * tokens.length + tokenIndex;

            if (rawBalances[index].gt(0)) {
              balances[address][token] = rawBalances[index].toFormat();
            }
          });
        });

        return balances;
      });
 */

pragma solidity ^0.4.10;

contract TokenReg {
  function tokenCount() constant returns (uint);
  function token(uint _id) constant returns (address addr, string tla, uint base, string name, address owner);
}

contract Tokens {
  function Tokens (address tokenRegAddress, uint start, uint limit)
  {
    TokenReg tokenReg = TokenReg(tokenRegAddress);

    uint tokensCount = tokenReg.tokenCount();
    uint count;

    // Prevent uint overflow
    assert(start + limit > start);

    if (tokensCount <= start) {
      count = 0;
    } else if (start + limit > tokensCount) {
      count = tokensCount - start;
    } else {
      count = limit;
    }

    // The size is 32 bytes for each
    // value, plus 32 bytes for the count
    uint m_size = 32 * count + 32;

    address[] memory tokens;

    assembly {
      tokens := mload(0x40)
      mstore(0x40, add(tokens, m_size))
      mstore(tokens, count)
    }

    for (uint i = start; i < start + count; i++) {
      (tokens[i - start],) = tokenReg.token(i);
    }

    assembly {
      return (tokens, m_size)
    }
  }
}

contract TokensBalances {
  function TokensBalances (address[] memory who, address[] memory tokens)
  {
    uint count = tokens.length * who.length;

    // The size is 32 bytes for each
    // value, plus 32 bytes for the count
    uint m_size = 32 * count + 32;
    bytes4 signature = 0x70a08231;

    uint[] memory balances;
    uint m_in;
    uint m_out;

    assembly {
      balances := mload(0x40)
      mstore(0x40, add(balances, m_size))
      mstore(balances, count)

      m_in := mload(0x40)
      mstore(0x40, add(m_in, 0x24))
      mstore(m_in, signature)

      m_out := balances
    }

    // The data is right after the first 4 signature bytes
    uint m_in_data = m_in + 4;

    for (uint i = 0; i < who.length; i++) {
      for (uint j = 0; j < tokens.length; j++) {
        address w = who[i];
        address t = tokens[j];

        assembly {
          m_out := add(m_out, 0x20)
          mstore(m_in_data, w)
          call(0xffff, t, 0x0, m_in, 0x24, m_out, 0x20)
          pop
        }
      }
    }

    assembly {
      return (balances, m_size)
    }
  }
}
