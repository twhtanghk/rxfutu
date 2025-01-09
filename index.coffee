_ = require 'lodash'
moment = require 'moment'
Promise = require 'bluebird'
import {from, filter, map, tap} from 'rxjs'
{freqDuration, Broker} = AlgoTrader = require('algotrader/rxData').default
import ftWebsocket from 'futu-api'
import { ftCmdID } from 'futu-api'
import {Common, Qot_Common, Trd_Common} from 'futu-api/proto'
{TradeDateMarket, SubType, RehabType, KLType, QotMarket} = Qot_Common
{RetType} = Common
{ModifyOrderOp, OrderType, OrderStatus, SecurityFirm, TrdEnv, TrdMarket, TrdSecMarket, TrdSide, TimeInForce} = Trd_Common

class Order extends AlgoTrader.Order
  @SIDE:
    unknown: TrdSide.TrdSide_Unknown
    buy: TrdSide.TrdSide_Buy
    buyBack: TrdSide.TrdSide_BuyBack
    sell: TrdSide.TrdSide_Sell
    sellShort: TrdSide.TrdSide_SellShort

  @TYPE:
    limit: OrderType.OrderType_Normal
    market: OrderType.OrderType_Market

  @STATUS:
    unsubmitted: OrderStatus.OrderStatus_Unsubmitted
    unknown: OrderStatus.OrderStatus_Unknown
    waitingSubmit: OrderStatus.OrderStatus_WaitingSubmit
    submitting: OrderStatus.OrderStatus_Submitting
    sumitFailed: OrderStatus.OrderStatus_SubmitFailed
    timeout: OrderStatus.OrderStatus_TimeOut
    submitted: OrderStatus.OrderStatus_Submitted
    filledPart: OrderStatus.OrderStatus_Filled_Part
    filledAll: OrderStatus.OrderStatus_Filled_All
    cancellingPart: OrderStatus.OrderStatus_Cancelling_Part
    cancellingAll: OrderStatus.OrderStatus_Cancelling_All
    cancelledPart: OrderStatus.OrderStatus_Cancelled_Part
    cancelledAll: OrderStatus.OrderStatus_Cancelled_All
    failed: OrderStatus.OrderStatus_Failed
    disabled: OrderStatus.OrderStatus_Disabled
    deleted: OrderStatus.OrderStatus_Deleted
    fillCancelled: OrderStatus.OrderStatus_FillCancelled

  constructor: (opts) ->
    super opts
    @side = (_.invert Order.SIDE)[@side] || @side
    @type = (_.invert Order.TYPE)[@type] || @type
    @status = (_.invert Order.STATUS)[@status] || @status
    @fillQty = opts.fillQty
    @fillAvgPrice = opts.fillAvgPrice

  @fromFutu: (i) ->
    {code, name, trdSide, orderType, orderStatus, orderID, orderStatus, price, qty, fillQty, fillAvgPrice, updateTimestamp, createTimestamp} = i
    new Order
      id: orderID.toNumber()
      code: code
      name: name
      side: trdSide
      type: orderType
      status: orderStatus
      price: price
      qty: qty
      fillQty: fillQty
      fillAvgPrice: fillAvgPrice
      updateTime: updateTimestamp
      createTime: createTimestamp

  toJSON: ->
    _.extend super(), {@fillQty, @fillAvgPrice}
      
class Account extends AlgoTrader.Account
  serialNo: 0

  constructor: (opts) ->
    super()
    {broker, trdEnv, accID, trdMarketAuthList, accType, cardNum, securityFirm} = opts
    @broker = broker
    @id = accID
    @trdEnv = trdEnv
    @market = trdMarketAuthList
    @type = accType
    @cardNum = cardNum
    @securityFirm = securityFirm

  historyOrder: ({beginTime, endTime}={}) ->
    beginTime ?= moment().subtract week: 1
    endTime ?= moment()
    req =
      c2s:
        header:
          trdEnv: @trdEnv
          accID: @id
          trdMarket: @market
    openOrder = Futu.errHandler await @broker.ws.GetOrderList req
    req.c2s.filterConditions =
      beginTime: beginTime.format 'YYYY-MM-DD hh:mm:ss'
      endTime: endTime.format 'YYYY-MM-DD hh:mm:ss'
    history = Futu.errHandler await @broker.ws.GetHistoryOrderList req
    from (openOrder.orderList
      .concat history.orderList
      .map (order) ->
        (Order.fromFutu order).toJSON()
    )

  streamOrder: ->
    req =
      c2s:
        accIDList: [@id]
    await @broker.ws.SubAccPush req
    @broker
      .pipe filter ({type, data}) ->
        type == 'Trd_UpdateOrder'
      .pipe map ({type, data}) ->
        (Order.fromFutu data.order).toJSON()

  placeOrder: (order) ->
    super order
    req =
      c2s:
        packetID:
          connID: @broker.ws.getConnID()
          serialNo: @serialNo++
        header:
          trdEnv: @trdEnv
          accID: @id
          trdMarket: @market
        trdSide: Order.SIDE[order.side]
        orderType: Order.TYPE[order.type]
        code: order.code
        qty: order.qty
        price: order.price
        secMarket: TrdSecMarket.TrdSecMarket_HK
    Futu.errHandler await @broker.ws.PlaceOrder req

  cancelOrder: (order) ->
    req =
      c2s:
        packetID:
          connID: @broker.ws.getConnID()
          serialNo: @serialNo++
        header:
          trdEnv: @trdEnv
          accID: @id
          trdMarket: @market
        orderID: order.id
        modifyOrderOp: ModifyOrderOp.ModifyOrderOp_Cancel
    Futu.errHandler await @broker.ws.ModifyOrder req

  updateOrder: (order) ->
    req =
      c2s:
        packetID:
          connID: @broker.ws.getConnID()
          serialNo: @serialNo++
        header:
          trdEnv: @trdEnv
          accID: @id
          trdMarket: @market
        orderID: order.id
        qty: order.qty
        price: order.price
        modifyOrderOp: ModifyOrderOp.ModifyOrderOp_Normal
    Futu.errHandler await @broker.ws.modifyOrder req
    
  position: ->
    req =
      c2s:
        header:
          trdEnv: @trdEnv
          accID: @id
          trdMarket: @market[0]
    (Futu.errHandler await @broker.ws.GetPositionList req).positionList

class Futu extends Broker
  @marketMap:
    'hk': QotMarket.QotMarket_HK_Security
    'us': QotMarket.QotMarket_US_Securityx

  @subTypeMap:
    'Basic': SubType.SubType_Basic
    'Broker': SubType.SubType_Broker
    '1': SubType.SubType_KL_1Min
    '5': SubType.SubType_KL_5Min
    '15': SubType.SubType_KL_15Min
    '30': SubType.SubType_KL_30Min
    '1h': SubType.SubType_KL_60Min
    '1d': SubType.SubType_KL_Day
    '1w': SubType.SubType_KL_Week
    '1m': SubType.SubType_KL_Month
    '3m': SubType.SubType_KL_Quarter
    '1y': SubType.SubType_KL_Year

  @freqMap: Futu.subTypeMap

  @klTypeMap:
    '1': KLType.KLType_1Min
    '5': KLType.KLType_5Min
    '15': KLType.KLType_15Min
    '30': KLType.KLType_30Min
    '1h': KLType.KLType_60Min
    '1d': KLType.KLType_Day
    '1w': KLType.KLType_Week
    '1m': KLType.KLType_Month
    '3m': KLType.KLType_Quarter
    '1y': KLType.KLType_Year

  @constant: {
    Common
    KLType
    ModifyOrderOp
    OrderStatus
    OrderType
    Qot_Common
    QotMarket
    RehabType
    RetType
    SecurityFirm
    SubType
    TradeDateMarket
    Trd_Common
    TrdEnv
    TrdMarket
    TrdSide
    TrdSecMarket
  }

  @optCode: (code) ->
    [input, symbol, date, side, price, ...] = code.match /([A-Z]{3})([0-9]{6})([CP])([0-9]+)/
    side = {C: 'call', P: 'put'}[side]
    {symbol, date, side, price}

  trdEnv: if process.env.TRDENV? then parseInt process.env.TRDENV else TrdEnv.TrdEnv_Simulate

  constructor: ({host, port} = {}) ->
    super()
    host ?= 'futu'
    port ?= 33333
    global.WebSocket = require 'ws'
    return do =>
      await new Promise (resolve, reject) =>
        @ws = new ftWebsocket()
        @ws.start host, port, false, null
        @ws.onlogin = resolve
        @ws.onPush = (cmd, data) =>
          try
            @next
              type: (_.find ftCmdID, cmd: cmd).name
              data: Futu.errHandler data
          catch err
            @error err
      @

  @errHandler: ({errCode, retMsg, retType, s2c}) ->
    if retType != Futu.constant.RetType.RetType_Succeed
      throw new Error "#{errCode}: #{retMsg}"
    else
      s2c

  historyKL: ({market, code, start, end, freq}) ->
    security =
      market: Futu.marketMap[market]
      code: code
    rehabType = RehabType.RehabType_Forward
    klType = Futu.klTypeMap[freq]
    beginTime = (start || moment().subtract freqDuration[freq].dataFetched)
      .format 'YYYY-MM-DD'
    endTime = (end || moment())
      .format 'YYYY-MM-DD HH:mm:ss' 
    {klList} = Futu.errHandler await @ws.RequestHistoryKL c2s: {rehabType, klType, security, beginTime, endTime}
    from klList.map (i) ->
      {timestamp, openPrice, highPrice, lowPrice, closePrice, volume, turnover, changeRate} = i
      market: market
      code: code
      freq: freq
      timestamp: timestamp
      open: openPrice
      high: highPrice
      low: lowPrice
      close: closePrice
      volume: volume.toNumber()
      turnover: turnover
      changeRate: changeRate
    
  streamKL: ({market, code, freq}) ->
    opts = {market, code, freq}
    market ?= 'hk'
    market = Futu.marketMap[market]
    await @ws.Sub
      c2s:
        securityList: [{market, code}]
        subTypeList: [Futu.freqMap[freq]]
        isSubOrUnSub: true
        isRegOrUnRegPush: true
    kl = filter ({type, data}) ->
      {klType, security} = data
      type == 'Qot_UpdateKL' and 
      market == security.market and
      code == security.code and
      Futu.klTypeMap[freq] == klType
    transform = map ({type, data}) ->
      {timestamp, openPrice, highPrice, lowPrice, closePrice, volume, turnover} = data.klList[0]
      market: opts.market
      code: code
      freq: freq
      timestamp: timestamp
      open: openPrice
      high: highPrice
      low: lowPrice
      close: closePrice
      volume: volume.toNumber()
      turnover: turnover
    @pipe kl, transform 

  orderBook: ({market, code}) ->
    opts = {market, code}
    market ?= 'hk'
    market = Futu.marketMap[market]
    await @ws.Sub
      c2s:
        securityList: [{market, code}]
        subTypeList: [Futu.constant.SubType.SubType_OrderBook]
        isSubOrUnSub: true
        isRegOrUnRegPush: true
    orderBook = filter ({type, data}) ->
      if type == 'Qot_UpdateOrderBook'
        {security} = data
        {market, code} = security
        market == security.market and
        code == security.code
      else
        false
    transform = map ({type, data}) ->
      market: opts.market
      code: code
      ask: data.orderBookAskList
      bid: data.orderBookBidList  
    @pipe orderBook, transform

  unsubKL: ({market, code, freq}) ->
    opts = {market, code, freq}
    market ?= 'hk'
    market = Futu.marketMap[market]
    await @ws.Sub
      c2s:
        securityList: [{market, code}]
        subTypeList: [Futu.subTypeMap[freq]]
        isSubOrUnSub: false
        isRegOrUnRegPush: true

  unsubOrderBook: ({market, code}) ->
    opts = {market, code}
    market ?= 'hk'
    market = Futu.marketMap[market]
    await @ws.Sub
      c2s:
        securityList: [{market, code}]
        subTypeList: [Futu.constant.SubType.SubType_OrderBook]
        isSubOrUnSub: false
        isRegOrUnRegPush: true
    
  marketState: ({market, code}) ->
    market ?= 'hk'
    market = Futu.marketMap[market]
    (Futu.errHandler await @ws.GetMarketState 
      c2s: securityList: [{market, code}]).marketInfoList

  optionChain: ({market, code, strikeRange, beginTime, endTime}) ->
    market ?= 'hk'
    beginTime ?= moment()
      .startOf 'month'
    endTime ?= moment()
      .endOf 'month'
    {optionChain} = Futu.errHandler await @ws.GetOptionChain
      c2s:
        owner:
          market: Futu.marketMap[market]
          code: code
        beginTime: beginTime.format 'YYYY-MM-DD'
        endTime: endTime.format 'YYYY-MM-DD'
    _.map optionChain, ({option, strikeTime, strikeTimestamp}) ->
      strikeTime: strikeTime
      option: _.filter option, ({call, put}) ->
        {basic, optionExData} = call
        {strikePrice} = optionExData
        [min, max] = strikeRange
        min <= strikePrice and strikePrice <= max

  basicQuote: ({market, code}) ->
    market ?= 'hk'
    market = Futu.marketMap[market]
    await @ws.Sub
      c2s:
        securityList: [{market, code}]
        subTypeList: [Futu.constant.SubType.SubType_Basic]
        isSubOrUnSub: true
        isRegOrUnRegPush: true
    req =
      c2s:
        securityList: [{market, code}]
    [ret, ...] = (Futu.errHandler await @ws.GetBasicQot req).basicQotList
    ret

  plateSecurity: ({market, code} = {}) ->
    market ?= 'hk'
    market = Futu.marketMap[market]
    code ?= 'HSI Constituent'
    (Futu.errHandler await @ws.GetPlateSecurity
      c2s:
        plate: {market, code}).staticInfoList.map ({basic}) ->
          code: basic.security.code
          name: basic.name

  accounts: ->
    (Futu.errHandler await @ws.GetAccList c2s: userID: 0)
      .accList
      .filter ({trdEnv, trdMarketAuthList}) ->
        # real account and hk in market list
        trdEnv == 1 and 1 in trdMarketAuthList
      .map (acc) =>
        acc.broker = @
        new Account acc

  unlock: ({pwdMD5}) ->
    req =
      c2s:
        unlock: true
        securityFirm: SecurityFirm.SecurityFirm_FutuSecurities
        pwdMD5: pwdMD5
    Futu.errHandler await @ws.UnlockTrade req

export default Futu
