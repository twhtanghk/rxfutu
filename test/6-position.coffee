Futu = require('../index').default

broker = await new Futu()
console.log await (await broker.defaultAcc()).position()
