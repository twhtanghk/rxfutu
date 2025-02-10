_ = require 'lodash'
moment = require 'moment'
Futu = require '../index'
strategy = require 'algotrader/rxStrategy'
{ohlc} = require 'algotrader/analysis'
{skipDup} = ohlc
{createLogger} = winston = require 'winston'
{concatMap, tap, map, filter} = require 'rxjs'

logger = createLogger
  level: process.env.LEVEL || 'info'
  format: winston.format.simple()
  transports: [ new winston.transports.Console() ]

if process.argv.length != 5
  logger.error 'node -r coffeescript/register -r esm test/strategy code optCode meanReversion'
  process.exit 1

position = ({broker, market, code}) ->
  account = await broker.defaultAcc()
  found = (await account.position())
  found = found
    .find (i) ->
      code == i.code
  if found?
    _.pick found, [
      'code'
      'name'
      'qty'
      'canSellQty'
      'price'
      'costPrice'
      'plVal'
      'plRation'
    ]
  else
    code: code
    qty: 0
    canSellQty: 0

direction = ({entry, opt}) ->
  entry = {buy: 1, sell: -1}[entry]
  opt = {call: 1, put: -1}[opt]
  entry * opt

decision = ({entry, opt, canSellQty}) ->
  side = {buy: 'long', sell: 'short'}[entry]
  switch true
    when canSellQty == 0
      qty: direction({entry, opt}), opt: opt
    when canSellQty > 0
      qty: -1 * direction({entry, opt}) * canSellQty, opt: opt
    when canSellQty < 0
      qty: -1 * direction({entry, opt}) * canSellQty, opt: opt

# check position and active order
portfolio = ({broker, market, optCode}) -> (obs) ->
  obs
    .pipe concatMap (i) ->
      {canSellQty} = await position 
        broker: broker
        market: market
        code: optCode
      {i, canSellQty}
    .pipe map ({i, canSellQty}) ->
      {side} = Futu.optCode optCode
      _.merge i, entryExit: decision {entry: i.entryExit.side, opt: side, canSellQty: canSellQty}

do ->
  try 
    [..., code, optCode, selectedStrategy] = process.argv
    market = 'hk'
    freq = '5'
    broker = await new Futu()
    account = await broker.defaultAcc()
    opts =
      market: market
      code: code
      freq: freq
    (await broker.dataKL opts)
      .pipe filter (i) ->
        market == i.market and code == i.code and freq == i.freq
      .pipe skipDup 'timestamp'
      .pipe map (i) ->
        i.date = new Date i.timestamp * 1000
        i
      .pipe strategy.indicator()
      .pipe strategy.meanReversion()
      .pipe filter (i) ->
        'entryExit' of i
      .pipe filter (i) ->
        # filter those history data
        moment()
          .subtract minute: 2 * parseInt freq
          .isBefore moment.unix i.timestamp
      .pipe tap (x) -> logger.debug JSON.stringify x
      .pipe filter (i) ->
        i['close.stdev.stdev'] < 1 or i['close.stdev.stdev'] > 14
      .pipe portfolio {broker, market, optCode}
      .pipe tap (x) -> logger.debug JSON.stringify x
      .subscribe (i) ->
        price = (await broker.quickQuote({market, code: optCode}))[i.entryExit[0].side]
        params =
          code: optCode
          side: i.entryExit[0].side
          type: 'limit'
          price: price
        logger.info JSON.stringify params
        ###
        try
          index = await account.placeOrder params
          await account.enableOrder index
        catch err
          logger.error err
        ###
  catch err
    console.error err
