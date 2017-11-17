export default function (promise) {
  return promise
    .then(() => assert.fail('Expected throw not received'))
    .catch(error => assert(error.message.search('invalid opcode') >= 0, "Expected invalidOp, got '" + error + "' instead"))
};