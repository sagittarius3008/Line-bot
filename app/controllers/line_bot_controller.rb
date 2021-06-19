class LineBotController < ApplicationController
  protect_from_forgery except: [:callback]

  def callback
    body = request.body.read
    # StringIOクラスのreadメソッド リクエストのメッセージ（ボディ）を代入
    # 以下、署名の検証機能（LineMessagingApi SDKが提供）
    signature = request.env['HTTP_X_LINE_SIGNATURE']#ヘッダー情報参照
    unless client.validate_signature(body, signature)#clientはstrongparameterで定義
    # unless文、trueはスルーされて、falsseが返ってきたら中の処理を実行
      return head :bad_request
    end
      events = client.parse_events_from(body)#メッセージボディのevents以下の配列を取得
        events.each do |event|
          case event
          when Line::Bot::Event::Message#メッセージイベントかどうか。×トークに誰か入ったイベント
            case event.type
            when Line::Bot::Event::MessageType::Text#スタンプならsticker,画像はimage
            # search_and_create_messageでメッセージを作成している
              message = search_and_create_message(event.message['text'])
              client.reply_message(event['replyToken'], message)
              #リプライするときは返信するもの（message）と一緒にreplytplenをつける決まり
            end
          end
        end
      head :ok#署名の検証のレスポンス。OK！
  end

  private

     def client
       @client ||= Line::Bot::Client.new { |config|
      # @clientがnil,falseの場合右側を代入する
      # callbackで何度か呼び出すメソッド
      # ただし、インスタンス化は初めのみ。
      # インスタンス変数の@clientが定義された瞬間は、中身にnilが入っているため、
      # 右辺のコードが実行され、インスタンスが@clientに代入されます
      # 右辺の書き方は仕様なので、そんなもん程度の理解でOK
         config.channel_secret = ENV["LINE_CHANNEL_SECRET"]
         config.channel_token = ENV["LINE_CHANNEL_TOKEN"]
        # .ENVファイルで定義している環境変数の値が返る
       }
     end
    def search_and_create_message(keyword)
      # 引数としてLineアプリから送信されたメッセージをkeywordとして扱う
      http_client = HTTPClient.new
      url = 'https://app.rakuten.co.jp/services/api/Travel/KeywordHotelSearch/20170426'
      query = {
        # HTTPClientでパラメータを設定する
        # keywordはsearch_and_create_messageの引数
        'keyword' => keyword,
        # .envファイル内で設定した環境変数を呼び出す
        'applicationId' => ENV['RAKUTEN_APPID'],
        'hits' => 5,
        'responseType' => 'small',
        'datumType' => 1,
        'formatVersion' => 2
      }
      response = http_client.get(url, query)
      # 上でGETリクエストを送信してレスポンスを下のresponse変数にいれる。
      # 上の取得したのは文字列、扱いが面倒なのでJSON.parseメソッドでハッシュに変換
      response = JSON.parse(response.body)

      # ()内のキー名があればtrueを返す
      if response.key?('error')
         text = "この検索条件に該当する宿泊施設が見つかりませんでした。\n条件を変えて再検索してください。"
         {
        # Lineにテキストメッセージとして返信するためtypeはtext
         type: 'text',
         text: text
       }
      else
      # Stringクラスの変数だよ宣言
      # textの中にLINEへ送信するメッセージを入れる。
      # text = ''
      # ホテル情報を順々に入れる
      # response['hotels'].each do |hotel|
        # <<は演算子。すでに格納されている文字列に連結するかたちで代入する。
        # つまりホテルの情報がいくつも連続して一つのメッセージの形で返される
        # <<はstringクラスでしか使えない。
        # text <<
          # hotel[0]['hotelBasicInfo']['hotelName'] + "\n" +
          # hotel[0]['hotelBasicInfo']['hotelInformationUrl'] + "\n" +
          # "\n"
      # テキストメッセージではなくにぎやかな形で返す場合、typeはtextではなくflex
        {
         type: 'flex',
         altText: '宿泊検索の結果です。',
         contents: set_carousel(response['hotels'])
       }
      end
      {
         type: 'flex',
         altText: '宿泊検索の結果です。',
         contents: set_carousel(response['hotels'])
       }
  end

   def set_carousel(hotels)
    # バブルコンテナ（1つ1つのホテル情報表示するカード）の配列を作成、[]で配列を宣言
       bubbles = []
       hotels.each do |hotel|
        # pushは配列の末尾に要素を追加するメソッド
        # set_bubbleはset_bubbleメソッドを下に定義する。
         bubbles.push set_bubble(hotel[0]['hotelBasicInfo'])
       end
       {
        # カルーセルコンテナであることの宣言
         type: 'carousel',
        # 上で作ったバブルコンテナの配列を指定
         contents: bubbles
       }
     end

     def set_bubble(hotel)
       {
         type: 'bubble',
         hero: set_hero(hotel),
         body: set_body(hotel),
         footer: set_footer(hotel)
       }
     end

     def set_hero(hotel)
       {
         type: 'image',
         url: hotel['hotelImageUrl'],
         size: 'full',
         aspectRatio: '20:13',
         aspectMode: 'cover',
         action: {
           type: 'uri',
           uri:  hotel['hotelInformationUrl']
         }
       }
     end

    # ラインのflex message simulatorで作成したデータをベースに一部変更
     def set_body(hotel)
       {
         type: 'box',
         layout: 'vertical',
         contents: [
           {
             type: 'text',
            # ホテル名が格納されてる['hotelName']
             text: hotel['hotelName'],
             wrap: true,
             weight: 'bold',
             size: 'md'
           },
           {
             type: 'box',
             layout: 'vertical',
             margin: 'lg',
             spacing: 'sm',
             contents: [
               {
                 type: 'box',
                 layout: 'baseline',
                 spacing: 'sm',
                 contents: [
                   {
                     type: 'text',
                     text: '住所',
                     color: '#aaaaaa',
                     size: 'sm',
                     flex: 1
                   },
                   {
                     type: 'text',
                    # 都道府県とそれ以下の合成
                     text: hotel['address1'] + hotel['address2'],
                     wrap: true,
                     color: '#666666',
                     size: 'sm',
                     flex: 5
                   }
                 ]
               },
               {
                 type: 'box',
                 layout: 'baseline',
                 spacing: 'sm',
                 contents: [
                   {
                     type: 'text',
                     text: '料金',
                     color: '#aaaaaa',
                     size: 'sm',
                     flex: 1
                   },
                   {
                     type: 'text',
                    # 最安値の取得['hotelMinCharge']
                    # to_s(:delimited)でstringクラスにして、カンマ区切りにしている。
                    # 最安値＋～で"5,000~"という表示にしている
                     text: '￥' + hotel['hotelMinCharge'].to_s(:delimited) + '〜',
                     wrap: true,
                     color: '#666666',
                     size: 'sm',
                     flex: 5
                   }
                 ]
               }
             ]
           }
         ]
       }
     end

     def set_footer(hotel)
       {
         type: 'box',
         layout: 'vertical',
         spacing: 'sm',
         contents: [
           {
             type: 'button',
             style: 'link',
             height: 'sm',
             action: {
               type: 'uri',
               label: '電話する',
              # hotel['telephoneNo']で電話番号取得
              # 文字列結合して見やすく
               uri: 'tel:' + hotel['telephoneNo']
             }
           },
           {
             type: 'button',
             style: 'link',
             height: 'sm',
             action: {
               type: 'uri',
               label: '地図を見る',
              # googleマップのURLにホテルの緯度と経度を合成。
              # hotel['latitude']とかはintererクラスなのでstringに変換
               uri: 'https://www.google.com/maps?q=' + hotel['latitude'].to_s + ',' + hotel['longitude'].to_s
             }
           },
           {
             type: 'spacer',
             size: 'sm'
           }
         ],
         flex: 0
       }
     end
end
