unit LUX.FMX.Motion;

// 操作に応えて動くものの、滑らかさを測る（Windows の FMX。画面の試験から使う）
//
//【構成】
// ・TMotionProbe … 使う側が渡した「1 歩の操作」を、決めた回数だけ、実際の操作と同じ遅れ方になる形で繰り返し、
//                   (a) 画面に出た更新の間隔（Pace）か、(b) 途中の画面のコマ（Shots）を測る。
// ・(a) と (b) は、別々の回で測る（コマを取る処理が、更新の間隔を変えるため）。
// ・部品は、使う側（アプリの型・画面・色）を知らない。何を動かすかは「1 歩の操作」が、何が意図しないものかは「判定」が決める。
// ・TMotionLock … 窓を動かして測る試験を、機械の上で 1 つずつにする排他（名前付きの mutex）。
// ・TMotionCost … 画面を使わずに、1 回の更新の仕事の時間を測る（変更のたびに回す、速い確かめ）。
// ・TMotionProbe.Versus・ShotsVersus … 同じ操作を、アプリの窓と素の窓で続けて測り、自分の側の原因か、枠組みの限界かを決める
//                         （完成として渡すときに一度だけ回す、画面に出す確かめ）。
// ・TMotionProbe.Settle … 機械の負荷が線を下回るのを待って測り、重い区間を含んでいれば、また待って測り直す。
//
//【測る間の機械の負荷】（LUX.Windows.Load）
// ・ほかの負荷を止めて測らない：利用者のふだんの使い方（裏でほかの仕事が動いている機械）で滑らかなことが要件で、負荷を
//   止めた機械で測った値は、それを示さない。代わりに、測る間の負荷を記録し、ふだんの程度を超えた区間を含む測定を、無効にする。
// ・TMotionProbe は、作ると、機械全体の負荷を取る部品（TLoad）を持つ。TLoad は、専用の実行スレッドで 16 ms 余り（実際は
//   17〜19 ms）おきに取るので、測る主スレッドは、何も取らない（更新のたびに行うことは、変わらない）。
// ・Pace・Drift の結果（TMotionPace）は、測った間の負荷の並び（Trace。時刻は、始めを 0 にそろえる）と、その要約（Trace.Stats。
//   種類ごとの平均・いちばん悪い値）を持つ。結果を知らせるのは、終わりの時刻までの負荷を取り終えてから（TLoad.Await）。
// ・隣り合う時点の間（Gaps と同じ並び）ごとに、重なる負荷の区間のどれかが線を超えていれば「重い」（Heavys）。重い間が 1 つでも
//   あれば、その測定は無効（Valid が偽）。無効な測定の割合は、自分の側の速さを示さないので、Versus は判定しない（mvVoid）。
// ・Settle は、最後に取った負荷の値が、どの種類も線以下になるのを待ち（TLoad.Calm。時間で推し量らない）、測り、無効なら、
//   また待って測る。SETTLE_N 回続けて無効なら、最後の無効な結果を、そのまま知らせる（合間の無い負荷が続いている）。
// ・負荷の区間は 17〜19 ms ほどなので、重い区間は、画面の更新の 2〜3 回ぶんを、まとめて重いとする。どの間隔で、なぜかは、
//   LUX.Windows.Load の頭の説明にある。
//
//【二段の確かめ】
// ・確かめを二段にする理由：画面に出す試験は、利用者の画面と入力を占め、その間、利用者は作業できない。変更のたびには、
//   画面を使わない速い確かめを回し、画面に出す確かめは、完成として渡すときに一度だけ、短く行う。
// ・変更のたび：TMotionCost.Measure。見せないフォームで、1 歩ごとに「操作 → 並べ直し（IAlignRoot.Realign）→ フォームと同じ
//   大きさの、画面に出さない画像への描画（TCustomForm.PaintTo）」の時間を測る。窓を画面に出さないので、利用者の画面も入力も
//   占めず、TMotionLock も握らない（並べて走ってよい）。合格は、平均が予算（いちばん短い画面の更新の周期の半分）以内（いちばん悪い
//   1 歩は、OS の割り込みを拾うので、記録だけ）。TMotionCostVersus.Measure で、見せない素の窓と同じ歩を続けて測り、平均の
//   上乗せが予算の 1 割以内なら、枠組みの限界とする。
//   半分にするのは、ここで測らない、描いたものを画面へ出す段（Flush・Present）と合成の分を、周期の残りに残すため。
// ・完成として渡すとき：Versus。アプリの窓と、使う側が渡す素の窓（部品を載せない最小のフォーム）を画面に出し、同じ操作を、
//   交互に（A・B・A・B・A・B）、1 回 1 秒の PaceFor で 3 組測る（全体で約 6 秒）。
// ・「同じ程度」は、決め打ちの幅ではなく、その場で測った素の窓の揺れから決める。1〜2 秒の測定 1 回どうしは揺れが大きく（同じ起動の
//   素の窓どうしでも、引っかかりの割合が 0.7〜3.6 倍に、ずれたコマの割合が 4.3〜15.8% に散る）、決め打ちの幅（素の窓 ＋ 5 ms/s、
//   ＋ 1 ポイント）は、その揺れより狭く、同じ程度のものを自分の側の原因と判定する。交互に測るのは、負荷の揺れが、両方に同じく
//   効くようにするため。判定：アプリの中央の値が基準未満なら合格。そうでなく、アプリの中央の値が、素の窓の回のいちばん大きい値
//   （素の窓が、自分自身の揺れで届く所）以下なら、枠組みの限界。それより悪ければ、自分の側の原因。無効な回を含む組は除き、
//   有効な組が 2 つに満たなければ、判定しない。
// ・測る長さは、秒で渡す（PaceFor・ShotsFor。10 秒まで）。Pace は歩を 1 ミリ秒おきに進め、1 回の画面の更新に何歩も進むので、
//   歩の数では、測る長さが決まらない（画面の更新の数を歩の数にすると、1.5 秒のつもりが 0.4 秒で終わる）。
// ・途中の画面も、ShotsVersus で、同じく交互に 3 組調べて比べる。合格は、アプリの中央の値が 0（当てはまるコマが無い）。
//   どちらかの回が全部のコマに当てはまった（窓が見えていないのと区別できない）組も、除く。
// ・比べる 2 つの窓は、同じモニターの、重ならない所に置く（素の窓を、アプリの窓の右・左・下・上の収まる所へ移す）。重なると、
//   測っている窓の手前に、もう一方がかぶさり、写るものと描かれ方が変わる。
//
//【画面が使えないとき】
// ・画面に鍵がかかっている（入力のデスクトップを開けない：OpenInputDesktop が 0）・画面が切れている（画面の画素を読めない：
//   GetPixel が CLR_INVALID）間は、写し取る BitBlt が失敗し、写し取る先には中身の無いものが残る（1.5 秒で 7 万の、中身の無い
//   コマが判定に渡る）。描画の時刻も、画面に出たものではない（引っかかりの割合が 0.0 と出る）。
// ・Pace・Shots は、始めに画面が使えなければ、測らずに、無効な結果を知らせる。終わりにも確かめ、使えなければ無効。Shots は、
//   写し取りに 1 度でも失敗すれば、取るのをやめて無効にする。無効な結果は、Versus・ShotsVersus が判定しない（mvVoid）。
//   途中で鍵がかかって、終わりまでに外れたときは、Shots は写し取りの失敗で分かるが、Pace は分からない（確かめていない）。
//
//【前に出す・かぶさりを確かめる】（Shots）
// ・測る部品は、測る相手の窓を作り直さない（測るものが、測られる物を変えない）。作った時の窓（HWND）に結び付いた中身（埋め込みの
//   ページのコントローラーの親・DirectComposition の描く先）を持つ窓は、作り直しに耐えず、その後の描画で落ちる（FormStyle を
//   StayOnTop に替えると、FMX は窓を作り直す：TCommonCustomForm.SetFormStyle → Recreate。だから、FormStyle は替えない）。
// ・写し取る前に、窓を作り直さない手段（SetForegroundWindow・BringWindowToTop）で、フォームを前に出す。
// ・写し取るたびに、その前と後で、写し取る範囲の点（四隅・真ん中・範囲と窓の見える枠が交わる所の真ん中）のいちばん上の窓
//   （WindowFromPoint の最上位の窓）を確かめる（TMotionProbe.Exposed）。窓の見える枠の内の点は、測る窓でなければならない。
//   枠の外の点（窓の端を後ろの板の色で見つける試験は、範囲を窓の外まで伸ばす）は、測る窓か、測っているのと同じプロセスの窓
//   （試験が出している後ろの板）ならよい。ほかのプロセスの窓が、どの点でもいちばん上なら（前に出せなかった・かぶさった）、
//   そのコマは判定せず、取るのをやめ、測定を無効にする（HidesN）。範囲と枠が交わらなければ、測る窓は写らないので、無効。
// ・写し取る実行スレッドは、座標を物理の画素にそろえる（DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2）：見える枠は、いつも
//   物理の画素で返る。DPI を知らないアプリでは、写し取る範囲（フォームの中のピクセル）も、物理の画素として読む（確かめていない）。
//
//【1 つずつ測る】（TMotionLock）
// ・窓を動かして測る試験が、ほかのプログラムの同じ試験と同時に走ると、窓が重なり、測った値と画面の写しが狂う。そこで、
//   窓を動かす試験のプログラムは、名前付きの mutex（NAME_DEFAULT）を握ってから窓を出し、プログラムが終わるまで握り続ける。
// ・TMotionProbe を作ると、Default を握る（まだ握っていなければ）。放すのは、プログラムの終わり（このユニットの後始末）。
//   測る部品を 1 つ作って捨て、また作る、の間に、ほかのプログラムの試験が割り込まない。窓を出す前から握るには、
//   試験のプログラムの始め（フォームを作る前）に、TMotionLock.Default.Acquire を呼ぶ。窓の試験の後に、窓を出さない試験が
//   長く続くなら、そこで Default.Release を呼んでよい。
// ・握れなければ、空くまで待つ（主スレッドで待つので、待つ間は、何も動かず、何も測らない）。時間で諦めない。待った時間は Waited。
// ・握ったプロセスが落ちると、Windows が、その mutex を「放棄された」として放し、次に待っていたものが握る（WAIT_ABANDONED。
//   守っているのは画面を使っていることだけで、直すべき途中の状態は無いので、ふつうに握れたものとして扱う）。
// ・名前は Local（ログオンのセッションの中）にする。窓と画面は、セッションごとに別で、ほかのセッションの試験の窓は、
//   この画面に重ならないので、セッションをまたいで待たせる理由が無い。
// ・mutex は、握ったスレッドのもの。放すのも、そのスレッドで行う（ほかのスレッドから放すと、例外）。
// ・測る窓は、画面に出したまま測る。Shots は画面から写し取るので、隠した窓（DWMWA_CLOAK）・画面の外の窓では写らない。
//   Pace・Drift も、窓を隠すと、画面へ出す経路（合成）が変わり、測るものが変わりうるので、隠さない。
//
//【操作の繰り返し方】
// ・1 歩ごとに、届けられる知らせ（TThread.ForceQueue）として、1 ミリ秒おきに行う。マウスの移動が、続けて届くのに近い：
//   届けられる知らせが続く間、窓の描き直し（WM_PAINT）は、後に回される。
// ・タイマーで動かすと、この遅れは再現しない（WM_TIMER は、WM_PAINT より後に回るので、毎回、描き直しが間に合う）。
// ・歩の間は、時計を見ながら待つ。Sleep は使わない：Windows の Sleep( 1 ) は、既定では、15 ミリ秒ほど眠るので、
//   歩の間が、決めた値にならず、測った間隔に、道具の待ちが混ざる。
//
//【タイマーで動くものの測り方】（Drift）
// ・FMX が、自分のタイマーで動かすもの（スクロールの位置の反映・慣性・アニメーション）は、上の繰り返し方では、歩の間、
//   動かない：タイマーの知らせ（WM_TIMER）も、届けられた知らせが残っている間は、来ない。
// ・Drift は、歩を、タイマーの刻みで進める。歩と歩の間、順番待ちが空になるので、FMX のタイマーも、窓の描き直しも、動く。
//   操作を 1 度だけ与えて、その後の動きを測るときは、最初の歩でだけ操作し、残りの歩では、何もしない。
// ・歩の間は、Windows のタイマーの細かさ（約 16 ミリ秒）より、細かくならない。
// ・変わるものが無い間は、描かれないので、間隔は長くなる。間隔を合否に使えるのは、歩ごとに、または歩の間じゅう、
//   何かが動いているときだけ。
//
//【画面に出た更新の数え方】
// ・FMX のフォームが、1 回描き終えるごとに、1 つと数える：フォームの公開のイベント OnPaint。FMX.Forms の TCustomForm.PaintRects が、
//   1 回の描画（BeginScene 〜 EndScene）の中で、1 度だけ呼ぶ。直後の EndScene で、画面に出る。
//   測る間だけ、フォームの OnPaint を借りる（元の手続きも呼ぶ）。終わったら、戻す。
// ・測るのは、始めから終わりまでの、隣り合う時点（始め・更新・…・終わり）の間隔。更新が 1 度も無ければ、全体が、1 つの間隔になる。
// ・更新のたびに行うのは、時刻を読んで並びに足すことだけ（測ることで、間隔を変えない）。
// ・FMX の外が描くもの（埋め込みの子の窓の中身）の更新は、数えない。それが FMX の描くものとずれていないかは、(b) のコマで調べる。
//
//【引っかかりの割合】（Apple「Eliminate animation hitches with XCTest」WWDC20 の物差し）
// ・Apple の物差しは、画面に出た時刻で数える。画面は、更新の周期ごとの刻みで新しい姿を出し、前の姿が出た刻みの次の刻みに、
//   次の姿が出るはずである。それより遅れて出たとき、飛ばした刻みの数 × 周期が、その引っかかりの時間。
// ・FMX は、垂直同期を待たずに画面へ出し（FMX.Canvas.D2D の Present( 0, 0 )）、合成は刻みごとに行われるので、描き終えた姿は、
//   その時刻の後の最初の刻みで画面に出る。そこで、描き終えた時刻（OnPaint）を、刻みの番号（境目を越えた数の切り上げ）に直し、
//   隣り合う時点の番号が 2 つ以上進んだ所で、飛ばした刻みの数（進んだ数 − 1）× 周期を足す。同じ刻みに 2 つ入ったもの（進んだ
//   数 0）は、前のものが画面に出なかっただけで、遅れではない。描いた時刻の間隔が周期の前後に揺れているだけ（どれも次の刻みに
//   間に合っている）なら、引っかかりは 0。
// ・刻みの境目の位相（垂直同期の時刻）は、測っていない。位相は、飛ばした刻みの数がいちばん少なくなるもの（いちばん間に合う
//   見方）にする。周期の 1.5 倍おきに描くような、本当に間に合っていない並びは、どの位相でも飛ばした数が変わらない。
// ・引っかかりの割合（ms/s）＝ 引っかかりの時間の合計 ÷ 始めから終わりまでの時間。合格は HITCH_LIMIT（5 ms/s）未満
//   （5 以上 10 未満は、利用者が気づき始める。10 以上は、目立つ）。
// ・始めと終わりも、時点に入れる。更新が 1 度も無ければ、始めから終わりまでの刻みを、ほぼ全部飛ばしたことになる。
//   始めから最初の更新までは、最初の 1 回の描画の遅れで、終わりの前は、最後の更新の後の待ち。どちらも、1 つの間隔ぶん。
//   歩の数を多くして、全体の時間に比べて小さくする。
// ・周期は、測り始める時の、フォームの窓のモニターから取る（LUX.Windows.Monitor）。周期が分からないモニターでは、測れない（例外）。
// ・Drift で、歩の間が周期より長いときは、歩と歩の間の刻みが、そのまま飛ばした刻みに数えられる（中身が、刻みごとには
//   変わらないため）。そのときの割合は、FMX のタイマーの細かさを含んだ値として読む。
//
//【コマの取り方】
// ・裏の実行スレッドが、画面（合成された後の、実際に見えているもの）から、フォームの中の指定の範囲を、続けて写し取る。
//   取る間、フォームを、いちばん手前に置く（ほかの窓に隠れていると、その窓が写る。【手前に置く】）。終わったら、戻す。
// ・コマごとに、使う側の判定（そのコマに、意図しないものが出ているか）を呼び、当てはまったコマを数える。
//   判定は、裏の実行スレッドで呼ばれる（画面の部品に、触らないこと）。
//
//【前提】
// ・主スレッドで使う。結果は、主スレッドで、渡した手続きに知らせる。1 度に測れるのは、1 つ。
// ・破棄すると、続きの歩は行わず、結果も知らせない。

interface //#################################################################### ■

uses Winapi.Windows,
     System.SysUtils, System.Types, System.UITypes, System.Classes, System.Diagnostics, System.Generics.Collections,
     FMX.Types, FMX.Controls, FMX.Graphics, FMX.Forms,
     LUX.Windows.Load;

type //$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 T Y P E 】

     TMotionLock  = class;
     TMotionProbe = class;

     // 1 歩の操作。Step_：何歩目か（0 から）
     TMotionStep = reference to procedure( const Step_:Integer );

     // フォームを受ける 1 歩の操作（同じ操作を、アプリの窓と素の窓に与えるため）。Form_：操作するフォーム。Step_：何歩目か（0 から）
     TMotionFormStep = reference to procedure( const Form_:TCustomForm; const Step_:Integer );

     // 素の窓との比べの判定
     TMotionVerdict = ( mvPassed,     // 基準（HITCH_LIMIT）を満たす
                        mvLimit,      // 基準を外れるが、素の窓と同じ程度（枠組みの限界）
                        mvOwnCause,   // 素の窓より悪い（自分の側の原因）
                        mvVoid );     // 有効な組（アプリと素の窓の、どちらの回も有効）が 2 つに満たない。判定しない

     // 写し取る範囲の 1 点で、いちばん上に見えている窓
     TMotionSpot = ( msOwn,           // 測る窓
                     msSibling,       // 測っているのと同じプロセスの、ほかの窓（試験が出している後ろの板など）
                     msOther );       // ほかのプロセスの窓（かぶさった）

     // 画面の上の点で、いちばん上に見えている窓を答える
     TMotionTop = reference to function( const Point_:TPoint ) :TMotionSpot;

     //$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 R E C O R D 】

     //%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% TMotionPace

     // 更新の間隔を測った結果
     TMotionPace = record
       UpdatesN :Integer;          // 画面に出た更新の数
       Worst    :Double;           // 間隔の、いちばん悪い値（ミリ秒）
       Over60N  :Integer;          // 1/60 秒を超えた間隔の数
       Over30N  :Integer;          // 1/30 秒を超えた間隔の数
       Elapse   :Double;           // 始めから終わりまでの時間（ミリ秒）
       Gaps     :TArray<Double>;   // 間隔の並び（ミリ秒。始めから順に。どこで遅れたかを調べるため）
       Period   :Double;           // 画面の更新の周期（ミリ秒）
       Hitch    :Double;           // 引っかかりの時間の合計（ミリ秒）
       Ratio    :Double;           // 引っかかりの割合（ミリ秒／秒）
       Trace    :TLoadTrace;       // 測った間の機械の負荷の並びと要約（時刻は、始めが 0）
       Heavys   :TArray<Boolean>;  // 隣り合う時点の間ごと（Gaps と同じ並び）に、負荷が線を超えた区間に重なるか
       HeavysN  :Integer;          // 重い間の数
       Shown    :Boolean;          // 始めと終わりに、画面が使えた（鍵がかかっていない・切れていない）
       Valid    :Boolean;          // 画面が使えて、重い間が 1 つも無い（割合を、自分の側の速さとして読んでよい）
       // Times_：時点（始めからのミリ秒。始め・更新・…・終わりの順。2 つ以上）。Period_：画面の更新の周期（ミリ秒。正）。
       // Trace_：同じ時計（始めが 0）の、測った間の負荷。Shown_：始めと終わりに、画面が使えたか
       constructor Create( const Times_:array of Double; const Period_:Double; const Trace_:TLoadTrace; const Shown_:Boolean = True );
       ///// C O N S T A N T
       const HITCH_LIMIT = 5;      // 引っかかりの割合の、合格の上限（ミリ秒／秒。これ未満が合格）
     end;

     // 1 回の測定（Pace か Drift を呼び、結果を Done_ に渡す）。Settle が、測り直すたびに呼ぶ（結果の型の後でないと宣言できない）
     TMotionMeasure = reference to procedure( const Done_:TProc<TMotionPace> );

     //%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% TMotionVersus

     // 同じ操作を、アプリの窓と素の窓で、交互に ROUNDS 組（A・B・A・B…）測った結果
     TMotionVersus = record
       Apps    :TArray<TMotionPace>;  // アプリの窓の回（測った順）
       Bases   :TArray<TMotionPace>;  // 素の窓の回（測った順。Apps[ I ] と組）
       PairsN  :Integer;              // 有効な組（どちらの回も有効）の数
       AppMid  :Double;               // 有効な組の、アプリの割合の中央の値（ミリ秒／秒）
       BaseMid :Double;               // 有効な組の、素の窓の割合の中央の値（ミリ秒／秒）
       BaseMin :Double;               // 有効な組の、素の窓の割合のいちばん小さい値（素の窓の揺れの下端）
       BaseMax :Double;               // 有効な組の、素の窓の割合のいちばん大きい値（素の窓の揺れの上端）
       Verdict :TMotionVerdict;       // 判定
       // Apps_・Bases_：同じ数の、組になった回
       constructor Create( const Apps_,Bases_:array of TMotionPace );
       ///// C O N S T A N T
       const ROUNDS        = 3;       // 組の数
       const ROUND_SECONDS = 1;       // 1 回の長さ（秒。全体で ROUNDS × 2 × これ）
     end;

     //%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% TMotionCost

     // 画面を使わずに測った、1 回の更新の仕事の時間（1 歩の操作 → 並べ直し → 画面に出さない画像へ描く）
     TMotionCost = record
       Costs  :TArray<Double>;  // 歩ごとの時間（ミリ秒。始めから順に）
       Mean   :Double;          // 平均（ミリ秒）
       Worst  :Double;          // いちばん悪い値（ミリ秒）
       Budget :Double;          // 予算（ミリ秒。画面の更新の周期の半分）
       Passed :Boolean;         // 平均が、予算以内（いちばん悪い値は、記録だけ）
       // Costs_：歩ごとの時間（ミリ秒。1 つ以上）。Period_：画面の更新の周期（ミリ秒。正）
       constructor Create( const Costs_:array of Double; const Period_:Double );
       ///// M E T H O D
       // 見せないフォーム Form_ で、Step_ を StepsN_ 回行い、歩ごとに、並べ直しと、画面に出さない画像への描画までの時間を測る。
       // 周期は、全部のモニターのうちいちばん短いもの（TWinMonitor.MinPeriod）
       class function Measure( const Form_:TCustomForm; const StepsN_:Integer; const Step_:TMotionStep ) :TMotionCost; static;
     end;

     //%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% TMotionCostVersus

     // 同じ歩を、見せないアプリの窓と素の窓で、続けて測った、1 回の更新の仕事の時間
     TMotionCostVersus = record
       App     :TMotionCost;     // アプリの窓
       Base    :TMotionCost;     // 素の窓（部品を載せない最小のフォーム）
       Margin  :Double;          // 素の窓の平均からの上乗せの許し（ミリ秒。予算 × MARGIN_RATE）
       Verdict :TMotionVerdict;  // 判定
       constructor Create( const App_,Base_:TMotionCost );
       ///// C O N S T A N T
       const MARGIN_RATE = 0.1;  // 上乗せの許しの、予算に対する割合
       ///// M E T H O D
       // 同じ歩 Step_ を、見せないアプリの窓 App_ と、見せない素の窓 Base_ で、続けて測り（TMotionCost.Measure）、比べる
       class function Measure( const App_,Base_:TCustomForm; const StepsN_:Integer; const Step_:TMotionFormStep ) :TMotionCostVersus; static;
     end;

     //%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% TMotionShots

     // 途中の画面を調べた結果
     TMotionShots = record
       FramesN :Integer;  // 写し取って判定したコマの数
       BadsN   :Integer;  // 判定に当てはまった（意図しないものが出ていた）コマの数
       MissN   :Integer;  // 写し取りに失敗した回数（BitBlt が偽。判定していない）
       HidesN  :Integer;  // 写し取る範囲に、ほかの窓がかぶさっていた回数（判定していない）
       Elapse  :Double;   // 始めから終わりまでの時間（ミリ秒）
       Shown   :Boolean;  // 始めと終わりに、画面が使えた
       Rate    :Double;   // 当てはまったコマの割合（BadsN ÷ FramesN。コマが無ければ 0）
       Valid   :Boolean;  // 画面が使えて、写し取りの失敗も、ほかの窓のかぶさりも無く、コマが 1 つ以上ある（割合を読んでよい）
       constructor Create( const FramesN_,BadsN_,MissN_,HidesN_:Integer; const Elapse_:Double; const Shown_:Boolean );
     end;

     //%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% TMotionShotsVersus

     // 同じ操作を、アプリの窓と素の窓で、交互に TMotionVersus.ROUNDS 組、途中の画面を調べた結果
     TMotionShotsVersus = record
       Apps    :TArray<TMotionShots>;  // アプリの窓の回（測った順）
       Bases   :TArray<TMotionShots>;  // 素の窓の回（測った順。Apps[ I ] と組）
       PairsN  :Integer;               // 有効な組の数（どちらの回も有効で、全部のコマが当てはまってはいない）
       AppMid  :Double;                // 有効な組の、アプリの当てはまったコマの割合の中央の値
       BaseMid :Double;                // 有効な組の、素の窓の割合の中央の値
       BaseMin :Double;                // 有効な組の、素の窓の割合のいちばん小さい値
       BaseMax :Double;                // 有効な組の、素の窓の割合のいちばん大きい値
       Verdict :TMotionVerdict;        // 判定
       // Apps_・Bases_：同じ数の、組になった回
       constructor Create( const Apps_,Bases_:array of TMotionShots );
     end;

     //%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% TMotionFrame

     // 画面の 1 コマ（指定の範囲の写し）。判定に渡す。判定が終わった後は、使えない
     TMotionFrame = record
     private
       _Bits   :PCardinal;  // 画素の並び（上の行から。1 画素は $xxRRGGBB）
       _Width  :Integer;
       _Height :Integer;
     public
       ///// P R O P E R T Y
       property Width  :Integer read _Width ;               // 幅（ピクセル）
       property Height :Integer read _Height;               // 高さ（ピクセル）
       ///// M E T H O D
       function Pixel( const X_,Y_:Integer ) :TAlphaColor;  // 範囲の左上を 0,0 とする位置の、画素の色（不透明）
     end;

     // コマの判定。そのコマに、意図しないもの（地・前の状態の残り・ずれ）が出ていれば、真
     TMotionJudge = reference to function( const Frame_:TMotionFrame ) :Boolean;

     //$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 C L A S S 】

     //%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% TMotionLock

     // 窓を動かして測る試験を、機械の上で 1 つずつにする排他（名前付きの mutex。握ったスレッドのもの）
     TMotionLock = class
     private
       class var _Default :TMotionLock;  // 測る部品が使うもの（初めて使うときに作り、ユニットの後始末で放して壊す）
       var
       _Name   :String;
       _Handle :THandle;                 // mutex（所有する）
       _Owner  :TThreadID;               // 握っているスレッド（握っていなければ 0）
       _Waited :Double;                  // 最後に握るまでに待った時間（ミリ秒）
       ///// A C C E S S O R
       function GetHeld :Boolean;
       class function GetDefault :TMotionLock; static;
     protected
     public
       // Name_：mutex の名前（同じ名前どうしが、1 つずつになる）
       constructor Create( const Name_:String );
       destructor Destroy; override;
       ///// P R O P E R T Y
       property Name   :String  read _Name   ;               // mutex の名前
       property Held   :Boolean read GetHeld ;               // このスレッドが握っているか
       property Waited :Double  read _Waited ;               // 最後に握るまでに待った時間（ミリ秒）
       class property Default :TMotionLock read GetDefault;  // 測る部品が使う排他（名前は NAME_DEFAULT）
       ///// C O N S T A N T
       const NAME_DEFAULT = 'Local\LUXOPHIA.MotionProbe';
       ///// M E T H O D
       procedure Acquire; virtual;                           // 握る。空くまで待つ。このスレッドが既に握っていれば、何もしない
       procedure Release; virtual;                           // 放す。握っていなければ、何もしない
     end;

     //%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% TMotionProbe

     // 操作を繰り返して、更新の間隔か、途中の画面を測る
     TMotionProbe = class
     private
       _Form    :TCustomForm;
       _Life    :IInterface;     // 生きている印（後に回した歩が、破棄の後に動かないように。実体は、実装部の TMotionLife）
       _StepsN  :Integer;        // 繰り返す回数（0 なら、測っていない）
       _Step    :TMotionStep;
       _Finish  :TProc;          // 最後の 1 歩の後に行うこと
       _Watch   :TStopwatch;
       _Times   :TList<Double>;  // 時点（始めからのミリ秒）：始め・更新・…・終わり
       _OnPaint :TOnPaintEvent;  // 借りる前の、フォームの OnPaint
       _Grab    :TThread;        // コマを取る実行スレッド（取っている間だけ）
       _Timer   :TTimer;         // Drift の歩を進めるタイマー
       _Next    :Integer;        // Drift の、次の歩
       _Period  :Double;         // 画面の更新の周期（ミリ秒。更新の間隔を測るとき、始める時に取る）
       _Load    :TLoad;          // 機械全体の負荷を取る部品（所有する）
       _Head    :Double;         // 測り始めた時刻（TLoad.Now の時計。ミリ秒）
       _Until   :Double;         // 歩を進める長さ（始めからのミリ秒。これを過ぎたら、次の歩を行わない）
       ///// M E T H O D
       function ScreenPeriod :Double;
       procedure Begins( const StepsN_:Integer; const Until_:Double; const Step_:TMotionStep );
       procedure Start( const StepsN_:Integer; const Until_:Double; const Step_:TMotionStep );
       procedure PaceIn( const StepsN_:Integer; const Until_:Double; const Step_:TMotionStep; const Done_:TProc<TMotionPace> );
       procedure ShotsIn( const StepsN_:Integer; const Until_:Double; const Step_:TMotionStep; const Area_:TRect; const Judge_:TMotionJudge; const Done_:TProc<TMotionShots> );
       procedure Lift;
       class function Seconds( const Seconds_:Double ) :Double; static;
       procedure Walk( const I_:Integer );
       procedure Watch( const Done_:TProc<TMotionPace> );
       procedure Ended;
       procedure Leave;
       ///// E V E N T
       procedure FormPaint( Sender_:TObject; Canvas_:TCanvas; const ARect_:TRectF );
       procedure TimerTick( Sender_:TObject );
     protected
     public
       // Form_：測るフォーム。作ると、TMotionLock.Default を握り（空くまで待つ）、負荷を取り始める
       constructor Create( const Form_:TCustomForm );
       destructor Destroy; override;
       ///// P R O P E R T Y
       property Load :TLoad read _Load;                                                                                                                               // 機械全体の負荷を取る部品（Settle に渡す）
       ///// C O N S T A N T
       const SETTLE_N = 5;                                                                                                                                            // Settle が測る、いちばん多い回数
       ///// M E T H O D
       // (a) 更新の間隔を測る。Step_ を StepsN_ 回繰り返し、終わったら、Done_ に結果を知らせる
       procedure Pace( const StepsN_:Integer; const Step_:TMotionStep; const Done_:TProc<TMotionPace> ); virtual;
       // (a) 更新の間隔を測る。Step_ を、Seconds_ 秒の間、繰り返す（歩の進め方は Pace と同じ。1 回の画面の更新に、何歩も進む）
       procedure PaceFor( const Seconds_:Double; const Step_:TMotionStep; const Done_:TProc<TMotionPace> ); virtual;
       // (a) 更新の間隔を、タイマーで動くものについて測る。Step_ を、Gap_ ミリ秒おきに、StepsN_ 回行う（歩の間、順番待ちが空になる）。
       //     最後の歩の後、もう 1 刻み待ってから、Done_ に結果を知らせる
       procedure Drift( const StepsN_,Gap_:Integer; const Step_:TMotionStep; const Done_:TProc<TMotionPace> ); virtual;
       // (b) 途中の画面を調べる。Area_：写し取る範囲（フォームの中の、ピクセル）。Judge_：コマの判定
       procedure Shots( const StepsN_:Integer; const Step_:TMotionStep; const Area_:TRect; const Judge_:TMotionJudge; const Done_:TProc<TMotionShots> ); virtual;
       // (b) 途中の画面を、Seconds_ 秒の間、調べる
       procedure ShotsFor( const Seconds_:Double; const Step_:TMotionStep; const Area_:TRect; const Judge_:TMotionJudge; const Done_:TProc<TMotionShots> ); virtual;  // 同じ操作 Step_ を、App_（アプリの窓）と Base_（素の窓）で、交互に（A・B・A・B・A・B）、1 回 ROUND_SECONDS 秒の PaceFor で
       // ROUNDS 組測り、回ごとの結果と判定を、Done_ に知らせる（全体で約 6 秒）。どちらの窓も、画面に出しておく（素の窓は、
       // 重ならない所へ移す）。測る間、TMotionLock.Default を握る。どの回も、Settle で測る（重い負荷の区間を避けて、測り直す）
       class procedure Versus( const App_,Base_:TCustomForm; const Step_:TMotionFormStep; const Done_:TProc<TMotionVersus> ); static;
       // 同じ操作 Step_ を、App_ と Base_ で、交互に、1 回 ROUND_SECONDS 秒の ShotsFor で ROUNDS 組調べ、回ごとの結果と判定を、
       // Done_ に知らせる。Area_ と Judge_ は、両方の窓に使う（素の窓は、アプリの窓と同じ大きさで作っておく）
       class procedure ShotsVersus( const App_,Base_:TCustomForm; const Step_:TMotionFormStep; const Area_:TRect; const Judge_:TMotionJudge; const Done_:TProc<TMotionShotsVersus> ); static;
       // 写し取る範囲 Area_（画面の座標）が、測る窓（見える枠 Frame_）を、ほかのプロセスの窓にかぶさられずに写すか。
       // 点（範囲の四隅・真ん中・範囲と枠が交わる所の真ん中）ごとに、枠の内なら、いちばん上が測る窓、枠の外なら、測る窓か、
       // 同じプロセスの窓であることを求める。範囲と枠が交わらなければ、偽（測る窓が写らない）。Top_：点のいちばん上の窓
       class function Exposed( const Area_,Frame_:TRect; const Top_:TMotionTop ) :Boolean; static;
       // 画面を写し取れるか：入力のデスクトップを開ける（画面に鍵がかかっていない）、かつ、窓 Wnd_ の場所の画素を、画面から読める
       // （画面が切れていない）
       class function ScreenOpen( const Wnd_:HWND ) :Boolean; static;
       // 素の窓 Base_ を、アプリの窓 App_ と同じモニターの、見える枠が重ならない所へ移す（重なっていなければ、動かさない）
       class procedure Apart( const App_,Base_:TCustomForm ); static;                                                                                                 // 測り直す口：Load_ の最後の値が、どの種類も線以下になるのを待って Measure_ で測り、結果が無効（重い間を含む）なら、
       // また待って測る。有効な結果か、SETTLE_N 回目の結果を、Done_ に知らせる（Done_ は、結果の Valid を見る）
       class procedure Settle( const Load_:TLoad; const Measure_:TMotionMeasure; const Done_:TProc<TMotionPace> ); static;
     end;

//$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 R O U T I N E 】

implementation //############################################################### ■

uses System.Math,
     Winapi.MultiMon, Winapi.DwmApi,
     FMX.Platform.Win,
     LUX.Windows.Monitor;

const
     STEP_MS = 1;          // 1 歩の間（ミリ秒）
     MS_60   = 1000 / 60;  // 1/60 秒（ミリ秒）
     MS_30   = 1000 / 30;  // 1/30 秒（ミリ秒）
     TICK_E  = 1E-9;       // 刻みの境目に載った時点を、浮動小数の誤りで、隣の刻みに入れないための許し（刻みの数）

// 時刻 Time_ が画面に出る、画面の更新の刻みの番号。刻みの境目は、Phase_ + 周期 × 整数。境目ちょうどの時刻は、その境目で出る
function TickOf( const Time_,Period_,Phase_:Double ) :Integer;
begin
     Result := Ceil( ( Time_ - Phase_ ) / Period_ - TICK_E );
end;

// 時点の並びを、境目の位相 Phase_ の刻みに置いたとき、隣り合う時点の間で飛ばした刻みの数の合計
function SkipsN( const Times_:array of Double; const Period_,Phase_:Double ) :Integer;
var
   I, K0, K1 :Integer;
begin
     Result := 0;

     K0 := TickOf( Times_[ 0 ], Period_, Phase_ );
     for I := 1 to High( Times_ ) do
     begin
          K1 := TickOf( Times_[ I ], Period_, Phase_ );

          if K1 - K0 >= 2 then Inc( Result, K1 - K0 - 1 );  // 同じ刻み（0）と、次の刻み（1）は、遅れていない

          K0 := K1;
     end;
end;

// Versus の次の回：測った回の並び Rs_ が、A・B・A・B…の何回目までかで、次に測る窓を決める（偶数回目はアプリ、奇数回目は素の窓）。
// 回ごとに測る部品を作り、Settle で測り、測る部品を後に回して壊してから、次の回へ。全部の回が済んだら、Done_ に並びを渡す
procedure PaceRounds( const App_,Base_:TCustomForm; const Step_:TMotionFormStep; const Rs_:TArray<TMotionPace>; const Done_:TProc<TArray<TMotionPace>> );
var
   F :TCustomForm;
   P :TMotionProbe;
begin
     if Length( Rs_ ) = 2 * TMotionVersus.ROUNDS then
     begin
          Done_( Rs_ );

          Exit;
     end;

     if Odd( Length( Rs_ ) ) then F := Base_
                             else F := App_;

     P := TMotionProbe.Create( F );

     TMotionProbe.Settle( P.Load, procedure( const D_:TProc<TMotionPace> )
                                  begin
                                       P.PaceFor( TMotionVersus.ROUND_SECONDS, procedure( const I_:Integer ) begin Step_( F, I_ ) end, D_ );
                                  end,
                          procedure( R_:TMotionPace )
                          begin
                               TThread.ForceQueue( nil, procedure
                               begin
                                    P.Free;

                                    PaceRounds( App_, Base_, Step_, Rs_ + [ R_ ], Done_ );
                               end );
                          end );
end;

// ShotsVersus の次の回（PaceRounds と同じ順）
procedure ShotsRounds( const App_,Base_:TCustomForm; const Step_:TMotionFormStep; const Area_:TRect; const Judge_:TMotionJudge; const Rs_:TArray<TMotionShots>; const Done_:TProc<TArray<TMotionShots>> );
var
   F :TCustomForm;
   P :TMotionProbe;
begin
     if Length( Rs_ ) = 2 * TMotionVersus.ROUNDS then
     begin
          Done_( Rs_ );

          Exit;
     end;

     if Odd( Length( Rs_ ) ) then F := Base_
                             else F := App_;

     P := TMotionProbe.Create( F );

     P.ShotsFor( TMotionVersus.ROUND_SECONDS, procedure( const I_:Integer ) begin Step_( F, I_ ) end, Area_, Judge_,
                 procedure( R_:TMotionShots )
                 begin
                      TThread.ForceQueue( nil, procedure
                      begin
                           P.Free;

                           ShotsRounds( App_, Base_, Step_, Area_, Judge_, Rs_ + [ R_ ], Done_ );
                      end );
                 end );
end;
// 値の中央（数が偶数なら、真ん中の 2 つの平均）。値が無ければ 0
function Median( const Values_:array of Double ) :Double;
var
   V :TArray<Double>;
   N, I :Integer;
begin
     N := Length( Values_ );

     if N = 0 then Exit( 0 );

     SetLength( V, N );
     for I := 0 to N - 1 do V[ I ] := Values_[ I ];
     TArray.Sort<Double>( V );

     if Odd( N ) then Result := V[ N div 2 ]
                 else Result := ( V[ N div 2 - 1 ] + V[ N div 2 ] ) / 2;
end;

// 組になった回の値（Apps_[ I ] と Bases_[ I ]）のうち、有効な組（Valids_[ I ]）だけで、アプリの中央の値と、素の窓の中央の値・
// いちばん小さい値・いちばん大きい値を求める。有効な組が無ければ、どれも 0
procedure Paired( const Apps_,Bases_:array of Double; const Valids_:array of Boolean; out PairsN_:Integer; out AppMid_,BaseMid_,BaseMin_,BaseMax_:Double );
var
   A, B :TArray<Double>;
   I :Integer;
begin
     if ( Length( Apps_ ) <> Length( Bases_ ) ) or ( Length( Apps_ ) <> Length( Valids_ ) ) then raise EArgumentException.Create( '組になった回の数が、そろっていない' );

     A := [];
     B := [];
     for I := 0 to High( Apps_ ) do
     begin
          if Valids_[ I ] then
          begin
               A := A + [ Apps_ [ I ] ];
               B := B + [ Bases_[ I ] ];
          end;
     end;

     PairsN_  := Length( A );
     AppMid_  := Median( A );
     BaseMid_ := Median( B );

     if PairsN_ > 0 then
     begin
          BaseMin_ := MinValue( B );
          BaseMax_ := MaxValue( B );
     end
     else
     begin
          BaseMin_ := 0;
          BaseMax_ := 0;
     end;
end;

// 比べの判定：有効な組が 2 つに満たなければ判定しない。アプリが基準を満たせば（Passed_）合格。満たさなくても、アプリの中央の値が、
// 素の窓の回のいちばん大きい値以下（素の窓が、自分自身の揺れで届く範囲の内）なら、枠組みの限界。それより悪ければ、自分の側の原因
function Judged( const PairsN_:Integer; const Passed_:Boolean; const AppMid_,BaseMax_:Double ) :TMotionVerdict;
begin
     if PairsN_ < 2           then Result := mvVoid
     else
     if Passed_               then Result := mvPassed
     else
     if AppMid_ <= BaseMax_   then Result := mvLimit
                              else Result := mvOwnCause;
end;
// Settle の N_ 回目：負荷が線以下になるのを待って測り、無効で、まだ SETTLE_N 回に満たなければ、次の回へ。
// 待ちは TLoad.Calm で、いつも後に回して知らせるので、回を重ねても、呼び出しは積み重ならない
procedure SettleFrom( const Load_:TLoad; const Measure_:TMotionMeasure; const Done_:TProc<TMotionPace>; const N_:Integer );
begin
     Load_.Calm( procedure
     begin
          Measure_( procedure( R_:TMotionPace )
          begin
               if R_.Valid or ( N_ >= TMotionProbe.SETTLE_N ) then Done_( R_ )
                                                              else SettleFrom( Load_, Measure_, Done_, N_ + 1 );
          end );
     end );
end;

// 窓の見える枠（画面の座標。DWMWA_EXTENDED_FRAME_BOUNDS）。窓の外枠（GetWindowRect）は、見えない縁を含む
function FrameOf( const Wnd_:HWND ) :TRect;
var
   H :HRESULT;
begin
     H := DwmGetWindowAttribute( Wnd_, DWMWA_EXTENDED_FRAME_BOUNDS, @Result, SizeOf( Result ) );

     if Failed( H ) then raise EOSError.CreateFmt( '窓の見える枠を読めない：%.8x', [ Cardinal( H ) ] );
end;
// TMotionProbe.Apart の中身（座標は、物理の画素。理由は Apart に）
procedure Place( const App_,Base_:TCustomForm );
var
   WA, WB :HWND;
   VA, VB, OB, R :TRect;
   M :TMonitorInfo;
   I :Integer;
   T :array [ 0..3 ] of TPoint;
begin
     WA := FormToHWND( App_  );
     WB := FormToHWND( Base_ );

     VA := FrameOf( WA );
     VB := FrameOf( WB );

     M := Default( TMonitorInfo );
     M.cbSize := SizeOf( M );

     if not GetMonitorInfo( TWinMonitor.Create( WA ).Handle, @M ) then RaiseLastOSError;

     // 同じモニターで、見える枠が重なっていない（辺が接するだけは、重なりではない）
     if ( TWinMonitor.Create( WB ).Handle = TWinMonitor.Create( WA ).Handle ) and not VA.IntersectsWith( VB ) then Exit;

     // 見える枠の置き場：右・左・下・上（アプリの窓の上端か左端にそろえる）
     T[ 0 ] := TPoint.Create( VA.Right          , VA.Top            );
     T[ 1 ] := TPoint.Create( VA.Left - VB.Width, VA.Top            );
     T[ 2 ] := TPoint.Create( VA.Left           , VA.Bottom         );
     T[ 3 ] := TPoint.Create( VA.Left           , VA.Top - VB.Height );

     GetWindowRect( WB, OB );  // 動かすのは外枠なので、見える枠との差（見えない縁）を足す

     for I := 0 to 3 do
     begin
          R := TRect.Create( T[ I ], VB.Width, VB.Height );

          if ( R.Left >= M.rcWork.Left ) and ( R.Top >= M.rcWork.Top ) and ( R.Right <= M.rcWork.Right ) and ( R.Bottom <= M.rcWork.Bottom ) then
          begin
               if not SetWindowPos( WB, 0, R.Left + ( OB.Left - VB.Left ), R.Top + ( OB.Top - VB.Top ), 0, 0, SWP_NOSIZE or SWP_NOZORDER or SWP_NOACTIVATE ) then RaiseLastOSError;

               Exit;
          end;
     end;

     raise EInvalidOpException.Create( '素の窓を、アプリの窓と重ならない所に置けない（同じモニターの作業領域に、2 つの窓が並ぶ大きさにする）' );
end;

type
     //%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% TMotionLife

     // 生きている印。後に回した手続きが持ち、持ち主が破棄されていたら、何もしない
     TMotionLife = class( TInterfacedObject )
     public
       Alive :Boolean;
     end;

     //%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% TMotionGrab

     // 画面から、窓の中の範囲を、続けて写し取って、判定に渡す実行スレッド
     TMotionGrab = class( TThread )
     private
       _Wnd     :HWND;
       _Area    :TRect;
       _Judge   :TMotionJudge;
       _FramesN :Integer;
       _BadsN   :Integer;
       _MissN   :Integer;
       _HidesN  :Integer;
       _Top     :TMotionTop;  // 点のいちばん上の窓を答える
       function Exposed( const Origin_:TPoint ) :Boolean;
     protected
       procedure Execute; override;
     public
       constructor Create( const Wnd_:HWND; const Area_:TRect; const Judge_:TMotionJudge );
       ///// P R O P E R T Y
       property FramesN :Integer read _FramesN;
       property BadsN   :Integer read _BadsN  ;
       property MissN   :Integer read _MissN  ;
       property HidesN  :Integer read _HidesN ;
     end;

//$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 R E C O R D 】

//%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% TMotionFrame

//&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&& public

//////////////////////////////////////////////////////////////////// M E T H O D

function TMotionFrame.Pixel( const X_,Y_:Integer ) :TAlphaColor;
var
   P :PCardinal;
begin
     if ( X_ < 0 ) or ( X_ >= _Width ) or ( Y_ < 0 ) or ( Y_ >= _Height ) then raise EArgumentOutOfRangeException.CreateFmt( 'コマの外の位置：%d, %d', [ X_, Y_ ] );

     P := _Bits;
     Inc( P, Y_ * _Width + X_ );

     Result := P^ or $FF000000;
end;

//%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% TMotionPace

//&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&& public

// 重い間：隣り合う時点の間（両端を含む）に重なる負荷の区間のどれかが、線を超えている。その間に画面に出たかどうか・出た時刻は、
// その区間の負荷の影響を受けうるので、その測定の割合は、自分の側の速さとして読めない
constructor TMotionPace.Create( const Times_:array of Double; const Period_:Double; const Trace_:TLoadTrace; const Shown_:Boolean );
var
   I, S :Integer;
   D :Double;
begin
     if Length( Times_ ) < 2 then raise EArgumentException.Create( '時点は、始めと終わりの 2 つ以上' );
     if not ( Period_ > 0 ) then raise EArgumentOutOfRangeException.Create( '画面の更新の周期は、正' );

     Self := Default( TMotionPace );

     UpdatesN := Length( Times_ ) - 2;
     Elapse   := Times_[ High( Times_ ) ] - Times_[ 0 ];
     Period   := Period_;
     Trace    := Trace_;
     Shown    := Shown_;

     // 隣り合う時点の間隔と、その間が重いか
     SetLength( Gaps  , Length( Times_ ) - 1 );
     SetLength( Heavys, Length( Times_ ) - 1 );
     for I := 1 to High( Times_ ) do
     begin
          D := Times_[ I ] - Times_[ I - 1 ];

          if D < 0 then raise EArgumentException.Create( '時点は、時刻の順に並べる' );

          Gaps[ I - 1 ] := D;

          if D > Worst   then Worst := D;
          if D > MS_60   then Inc( Over60N );
          if D > MS_30   then Inc( Over30N );

          Heavys[ I - 1 ] := Trace_.Heavy( Times_[ I - 1 ], Times_[ I ] );

          if Heavys[ I - 1 ] then Inc( HeavysN );
     end;

     Valid := Shown and ( HeavysN = 0 );  // 画面が使えなかった間の時点は、画面に出たものではない

     // 画面の更新の刻みの位相は分からないので、いちばん間に合う位相で数える。飛ばした刻みの数は、境目が時点を越える所でだけ
     // 変わるので、境目を、どれかの時点にちょうど載せた位相だけを試せば足りる（時点の数の 2 乗の手間。測り終えた後に 1 度だけ行う）
     S := MaxInt;
     for I := 0 to High( Times_ ) do S := Min( S, SkipsN( Times_, Period_, Times_[ I ] - Floor( Times_[ I ] / Period_ ) * Period_ ) );

     Hitch := S * Period_;

     // 全体の時間が 0 なら、間隔がどれも 0 で、遅れも無い
     if Elapse > 0 then Ratio := Hitch / ( Elapse / 1000 );
end;

//%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% TMotionVersus

//&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&& public

// 「同じ程度」を、決め打ちの幅ではなく、その場で測った素の窓の揺れから決める：1〜2 秒の測定 1 回どうしは揺れが大きく（同じ起動の
// 素の窓どうしでも、割合が 0.7〜3.6 倍に散る）、決め打ちの幅（素の窓 ＋ 5 ms/s）は、その揺れより狭く、同じ程度のものを自分の側の
// 原因と判定する。そこで、アプリの窓と素の窓を交互に（負荷の揺れが、両方に同じく効くように）短い回で測り、アプリの中央の値が、
// 素の窓の回のいちばん大きい値（素の窓が、自分自身の揺れで届く所）以下なら、同じ程度とする。
// 無効な回（重い負荷の区間を含む・画面を使えなかった）を含む組は除く
constructor TMotionVersus.Create( const Apps_,Bases_:array of TMotionPace );
var
   A, B :TArray<Double>;
   V :TArray<Boolean>;
   I :Integer;
begin
     if Length( Apps_ ) <> Length( Bases_ ) then raise EArgumentException.Create( '組になった回の数が、そろっていない' );

     Self := Default( TMotionVersus );

     SetLength( Apps , Length( Apps_ ) );
     SetLength( Bases, Length( Apps_ ) );
     SetLength( A, Length( Apps_ ) );
     SetLength( B, Length( Apps_ ) );
     SetLength( V, Length( Apps_ ) );
     for I := 0 to High( Apps_ ) do
     begin
          Apps [ I ] := Apps_ [ I ];
          Bases[ I ] := Bases_[ I ];

          A[ I ] := Apps_ [ I ].Ratio;
          B[ I ] := Bases_[ I ].Ratio;
          V[ I ] := Apps_[ I ].Valid and Bases_[ I ].Valid;
     end;

     Paired( A, B, V, PairsN, AppMid, BaseMid, BaseMin, BaseMax );

     Verdict := Judged( PairsN, AppMid < TMotionPace.HITCH_LIMIT, AppMid, BaseMax );
end;

//%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% TMotionShots

//&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&& public

// ほかの窓がかぶさっていた回が 1 つでもあれば、無効：写したのは、測る窓ではない。
// 写し取れなかった回が 1 つでもあれば、無効：画面を写し取れない間（鍵がかかっている・切れている）は、BitBlt が偽を返し、
// 写し取る先には、前のコマか、中身の無いものが残る。それを判定に渡すと、写っていないものを数える
constructor TMotionShots.Create( const FramesN_,BadsN_,MissN_,HidesN_:Integer; const Elapse_:Double; const Shown_:Boolean );
begin
     FramesN := FramesN_;
     BadsN   := BadsN_;
     MissN   := MissN_;
     HidesN  := HidesN_;
     Elapse  := Elapse_;
     Shown   := Shown_;

     if FramesN > 0 then Rate := BadsN / FramesN
                    else Rate := 0;

     Valid := Shown and ( MissN = 0 ) and ( HidesN = 0 ) and ( FramesN > 0 );
end;

//%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% TMotionShotsVersus

//&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&& public

// 判定の考え方は、TMotionVersus と同じ（交互に測り、素の窓の回の揺れの範囲で比べる）。合格は、アプリの中央の値が 0（当てはまる
// コマが無い）。組は、どちらの回も有効で、どちらも全部のコマが当てはまってはいない（窓が一度も見えていないのと、区別できない）
// ときだけ数える
constructor TMotionShotsVersus.Create( const Apps_,Bases_:array of TMotionShots );
var
   A, B :TArray<Double>;
   V :TArray<Boolean>;
   I :Integer;
begin
     if Length( Apps_ ) <> Length( Bases_ ) then raise EArgumentException.Create( '組になった回の数が、そろっていない' );

     Self := Default( TMotionShotsVersus );

     SetLength( Apps , Length( Apps_ ) );
     SetLength( Bases, Length( Apps_ ) );
     SetLength( A, Length( Apps_ ) );
     SetLength( B, Length( Apps_ ) );
     SetLength( V, Length( Apps_ ) );
     for I := 0 to High( Apps_ ) do
     begin
          Apps [ I ] := Apps_ [ I ];
          Bases[ I ] := Bases_[ I ];

          A[ I ] := Apps_ [ I ].Rate;
          B[ I ] := Bases_[ I ].Rate;
          V[ I ] := Apps_[ I ].Valid and Bases_[ I ].Valid
                and ( Apps_ [ I ].BadsN < Apps_ [ I ].FramesN )
                and ( Bases_[ I ].BadsN < Bases_[ I ].FramesN );
     end;

     Paired( A, B, V, PairsN, AppMid, BaseMid, BaseMin, BaseMax );

     Verdict := Judged( PairsN, AppMid = 0, AppMid, BaseMax );
end;

//%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% TMotionCost

//&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&& public

// 合否は、平均で決める。画面を使わない測定は、1 回の更新に要る仕事の量を見るもので、いちばん悪い 1 歩は、OS の割り込み
// （ほかの仕事に CPU を取られた 1 回）を拾う（負荷のある機械では、素の窓でも、平均 2.16 ms に対して、いちばん悪い 1 歩が 5.14 ms
// になる）。いちばん悪い値は、記録として残す。
// 予算を周期の半分にする理由：1 回の更新の時間は、ここで測る仕事（操作・並べ直し・描画）のほかに、描いたものを画面へ出す段
// （EndScene の Flush・Present）と、合成（DWM）の分を含む。それらに、周期の残りの半分を残す
constructor TMotionCost.Create( const Costs_:array of Double; const Period_:Double );
var
   C :Double;
   I :Integer;
begin
     if Length( Costs_ ) < 1 then raise EArgumentException.Create( '歩ごとの時間は、1 つ以上' );
     if not ( Period_ > 0 ) then raise EArgumentOutOfRangeException.Create( '画面の更新の周期は、正' );

     Self := Default( TMotionCost );

     SetLength( Costs, Length( Costs_ ) );
     for I := 0 to High( Costs_ ) do
     begin
          C := Costs_[ I ];

          Costs[ I ] := C;

          Mean := Mean + C;

          if C > Worst then Worst := C;
     end;

     Mean   := Mean / Length( Costs_ );
     Budget := Period_ / 2;
     Passed := Mean <= Budget;
end;

//////////////////////////////////////////////////////////////////// M E T H O D

// 画面に出さない：フォームは見せないまま、描く先は、フォームと同じ大きさの画像（TBitmap）。並べ直しは、フォームの公開の口
// IAlignRoot.Realign、描画は TCustomForm.PaintTo（その画像のキャンバスへ、フォームの描画をそのまま行う）。
// 画像の大きさを、フォームの大きさに合わせ直す時間は、測らない（道具の手間）
class function TMotionCost.Measure( const Form_:TCustomForm; const StepsN_:Integer; const Step_:TMotionStep ) :TMotionCost;
var
   P :Double;
   A :IAlignRoot;
   B :TBitmap;
   S :Single;
   W, H, I :Integer;
   C :TArray<Double>;
   K :TStopwatch;
begin
     if StepsN_ < 1 then raise EArgumentOutOfRangeException.Create( '繰り返す回数は、1 以上' );
     if Form_.Visible then raise EInvalidOpException.Create( '画面を使わずに測るので、フォームは見せないでおく' );
     if not Supports( Form_, IAlignRoot, A ) then raise EInvalidOpException.Create( 'フォームを並べ直せない' );

     P := TWinMonitor.MinPeriod * 1000;

     if not ( P > 0 ) then raise EInvalidOpException.Create( '画面の更新の周期が分からないので、予算を決められない' );

     S := Form_.Handle.Scale;

     SetLength( C, StepsN_ );

     B := TBitmap.Create;
     try
          B.BitmapScale := S;

          for I := 0 to StepsN_ - 1 do
          begin
               K := TStopwatch.StartNew;

               Step_( I );

               K.Stop;

               // 描く先を、いまのフォームの大きさに合わせる（測らない）
               W := Round( Form_.ClientWidth  * S );
               H := Round( Form_.ClientHeight * S );
               if ( B.Width <> W ) or ( B.Height <> H ) then B.SetSize( W, H );

               K.Start;

               A.Realign;

               Form_.PaintTo( B.Canvas );

               K.Stop;

               C[ I ] := K.Elapsed.TotalMilliseconds;
          end;
     finally
          B.Free;
     end;

     Result := TMotionCost.Create( C, P );
end;
//%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% TMotionCostVersus

//&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&& public

// 判定：アプリの平均が予算以内なら合格。超えても、素の窓の平均 ＋ 許し（予算の 1 割）以内なら、枠組みの限界（素の窓でも
// かかる仕事）。それより悪ければ、自分の側の原因。許しは、自分の仕事を足してよい幅ではなく、続けて測った 2 つの平均の、
// 負荷の揺れによる差を吸うための幅：素の窓が予算を超える機械では、アプリが足してよい仕事は無いが、2 つの平均は、同じ仕事でも
// 揺れる。予算の 1 割（120 Hz で約 0.4 ms）は、それより大きな上乗せなら、予算に対して見える大きさの仕事を足した、とみなす幅
// （揺れの実際の大きさは、測っていない）
constructor TMotionCostVersus.Create( const App_,Base_:TMotionCost );
begin
     App    := App_;
     Base   := Base_;
     Margin := App.Budget * MARGIN_RATE;

     if App.Passed                           then Verdict := mvPassed
     else
     if App.Mean <= Base.Mean + Margin        then Verdict := mvLimit
                                              else Verdict := mvOwnCause;
end;

//////////////////////////////////////////////////////////////////// M E T H O D

class function TMotionCostVersus.Measure( const App_,Base_:TCustomForm; const StepsN_:Integer; const Step_:TMotionFormStep ) :TMotionCostVersus;
var
   A, B :TMotionCost;
begin
     A := TMotionCost.Measure( App_ , StepsN_, procedure( const I_:Integer ) begin Step_( App_ , I_ ) end );
     B := TMotionCost.Measure( Base_, StepsN_, procedure( const I_:Integer ) begin Step_( Base_, I_ ) end );

     Result := TMotionCostVersus.Create( A, B );
end;
//$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 C L A S S 】

//%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% TMotionGrab

//&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&& private

// 写し取る範囲（画面の上の左上が Origin_）を、ほかのプロセスの窓にかぶさられずに写すか（TMotionProbe.Exposed）。
// 測る窓の見える枠は、その時のものを読む（窓の大きさを変えている間も、追う）
function TMotionGrab.Exposed( const Origin_:TPoint ) :Boolean;
begin
     Result := TMotionProbe.Exposed( TRect.Create( Origin_, _Area.Width, _Area.Height ), FrameOf( _Wnd ), _Top );
end;
//&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&& protected

procedure TMotionGrab.Execute;
var
   W, H :Integer;
   S, M :HDC;
   B :TBitmapInfo;
   D, O :HGDIOBJ;
   P :TPoint;
   F :TMotionFrame;
   Q :Pointer;
begin
     // この実行スレッドの座標を、物理の画素にそろえる（見える枠 DWMWA_EXTENDED_FRAME_BOUNDS は、いつも物理の画素で返る。
     // ClientToScreen・WindowFromPoint・画面からの写し取りも、それにそろえる）
     SetThreadDpiAwarenessContext( DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2 );

     W := _Area.Width;
     H := _Area.Height;

     // 写し取る先：上の行から並ぶ、1 画素 4 バイトの絵
     B := Default( TBitmapInfo );
     B.bmiHeader.biSize        := SizeOf( B.bmiHeader );
     B.bmiHeader.biWidth       := W;
     B.bmiHeader.biHeight      := -H;
     B.bmiHeader.biPlanes      := 1;
     B.bmiHeader.biBitCount    := 32;
     B.bmiHeader.biCompression := BI_RGB;

     S := GetDC( 0 );
     M := CreateCompatibleDC( S );
     D := CreateDIBSection( M, B, DIB_RGB_COLORS, Q, 0, 0 );
     O := SelectObject( M, D );
     try
          F._Bits   := Q;
          F._Width  := W;
          F._Height := H;

          while not Terminated do
          begin
               // 範囲の、画面の上での位置（窓が動いても、追う）
               P := _Area.TopLeft;
               ClientToScreen( _Wnd, P );

               // ほかの窓がかぶさっていたら、判定せずに、取るのをやめる（写すのは、測る窓ではない。測定は無効）
               if not Exposed( P ) then
               begin
                    Inc( _HidesN );

                    Break;
               end;

               // 写し取れなかったら、判定せずに、取るのをやめる（写し取る先には、前のコマか、中身の無いものが残っている。
               // 1 度でも写し取れなければ、その測定は無効なので、続けても読めるコマは増えない）
               if not BitBlt( M, 0, 0, W, H, S, P.X, P.Y, SRCCOPY ) then
               begin
                    Inc( _MissN );

                    Break;
               end;

               GdiFlush;

               // 写し取る間に、かぶさった
               if not Exposed( P ) then
               begin
                    Inc( _HidesN );

                    Break;
               end;

               Inc( _FramesN );
               if _Judge( F ) then Inc( _BadsN );
          end;
     finally
          SelectObject( M, O );
          DeleteObject( D );
          DeleteDC( M );
          ReleaseDC( 0, S );
     end;
end;

//&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&& public

constructor TMotionGrab.Create( const Wnd_:HWND; const Area_:TRect; const Judge_:TMotionJudge );
begin
     // 点のいちばん上の窓：WindowFromPoint（その点の、いちばん上の見えている窓）の最上位の窓が、測る窓か、同じプロセスの窓か
     _Top := function( const Point_:TPoint ) :TMotionSpot
     var
        T :HWND;
        I :DWORD;
     begin
          T := GetAncestor( WindowFromPoint( Point_ ), GA_ROOT );

          if T = Wnd_ then Exit( msOwn );

          I := 0;
          GetWindowThreadProcessId( T, @I );

          if I = GetCurrentProcessId then Result := msSibling
                                     else Result := msOther;
     end;

     _Wnd   := Wnd_;
     _Area  := Area_;
     _Judge := Judge_;

     inherited Create( False );
end;

//%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% TMotionLock

//&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&& private

//////////////////////////////////////////////////////////////// A C C E S S O R

function TMotionLock.GetHeld :Boolean;
begin
     Result := _Owner = GetCurrentThreadId;
end;

//------------------------------------------------------------------------------

class function TMotionLock.GetDefault :TMotionLock;
begin
     if not Assigned( _Default ) then _Default := TMotionLock.Create( NAME_DEFAULT );

     Result := _Default;
end;

//&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&& public

constructor TMotionLock.Create( const Name_:String );
begin
     inherited Create;

     _Name := Name_;

     _Handle := CreateMutex( nil, False, PChar( _Name ) );  // 既にあれば、同じ mutex を開く

     if _Handle = 0 then RaiseLastOSError;
end;

destructor TMotionLock.Destroy;
begin
     if Held then Release;

     // ほかのスレッドが握ったままなら、そのスレッドが終わるときに、Windows が放す（放棄）
     if _Handle <> 0 then CloseHandle( _Handle );

     inherited;
end;

//////////////////////////////////////////////////////////////////// M E T H O D

procedure TMotionLock.Acquire;
var
   W :TStopwatch;
begin
     if Held then Exit;

     if _Owner <> 0 then raise EInvalidOpException.Create( 'TMotionLock：ほかのスレッドが、この排他を握っている（1 つの排他は、1 つのスレッドで使う）' );

     W := TStopwatch.StartNew;

     // 放棄された（握ったものが、放さずに終わった）mutex も、握れている
     case WaitForSingleObject( _Handle, INFINITE ) of
       WAIT_OBJECT_0, WAIT_ABANDONED: ;
     else
          RaiseLastOSError;
     end;

     _Owner  := GetCurrentThreadId;
     _Waited := W.Elapsed.TotalMilliseconds;
end;

procedure TMotionLock.Release;
begin
     if _Owner = 0 then Exit;

     if not Held then raise EInvalidOpException.Create( 'TMotionLock：握ったスレッドでないと、放せない' );

     if not ReleaseMutex( _Handle ) then RaiseLastOSError;

     _Owner := 0;
end;
//%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% TMotionProbe

//&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&& private

//////////////////////////////////////////////////////////////////// M E T H O D

// フォームの窓のモニターの、画面の更新の周期（ミリ秒）。分からなければ、測れないので、例外
function TMotionProbe.ScreenPeriod :Double;
begin
     Result := TWinMonitor.Create( FormToHWND( _Form ) ).Period * 1000;

     if not ( Result > 0 ) then raise EInvalidOpException.Create( 'フォームの窓のモニターの、画面の更新の周期が分からないので、引っかかりを測れない' );
end;

// 測り始める：歩の数と長さと操作を覚え、時計を動かす（負荷の時計での始めの時刻も、覚える。どちらも QueryPerformanceCounter）
procedure TMotionProbe.Begins( const StepsN_:Integer; const Until_:Double; const Step_:TMotionStep );
begin
     if _StepsN > 0 then raise EInvalidOpException.Create( '測っている途中に、もう 1 つは測れない' );
     if StepsN_ < 1 then raise EArgumentOutOfRangeException.Create( '繰り返す回数は、1 以上' );

     _StepsN := StepsN_;
     _Until  := Until_;
     _Step   := Step_;
     _Head   := TLoad.Now;
     _Watch  := TStopwatch.StartNew;
end;

// 測り始める：1 歩目を、届けられる知らせにする
procedure TMotionProbe.Start( const StepsN_:Integer; const Until_:Double; const Step_:TMotionStep );
var
   L :IInterface;
begin
     Begins( StepsN_, Until_, Step_ );

     L := _Life;

     TThread.ForceQueue( nil, procedure begin if TMotionLife( L ).Alive then Walk( 0 ) end );
end;

// I_ 歩目を行い、次の歩（歩の数か、長さに達したら、終わりの処理）を、届けられる知らせにする
procedure TMotionProbe.Walk( const I_:Integer );
var
   L :IInterface;
   N :Integer;
   W :TStopwatch;
begin
     _Step( I_ );

     L := _Life;
     N := I_ + 1;

     if ( N < _StepsN ) and ( _Watch.Elapsed.TotalMilliseconds < _Until ) then
     begin
          W := TStopwatch.StartNew;
          while W.Elapsed.TotalMilliseconds < STEP_MS do ;

          TThread.ForceQueue( nil, procedure begin if TMotionLife( L ).Alive then Walk( N ) end );
     end
     else
     begin
          // 終わりの処理は、最後の 1 歩が後に回した処理（部品の置き直しなど）の、後になる
          TThread.ForceQueue( nil, procedure begin if TMotionLife( L ).Alive then Ended end );
     end;
end;

// フォームが描き終えるたびに、時刻を残す。終わったら、終わりの時刻までの負荷を取り終えるのを待ち（TLoad.Await）、
// 間隔を数えて、Done_ に知らせる。待つ間に、この部品が壊されれば、知らせは動かない（TLoad の後始末が取り除く）
procedure TMotionProbe.Watch( const Done_:TProc<TMotionPace> );
begin
     _Times.Clear;
     _Times.Add( 0 );

     _OnPaint      := _Form.OnPaint;
     _Form.OnPaint := FormPaint;

     _Finish := procedure
     var
        T :TArray<Double>;
        P, H, E :Double;
        S :Boolean;
     begin
          _Form.OnPaint := _OnPaint;
          _OnPaint      := nil;

          _Times.Add( _Watch.Elapsed.TotalMilliseconds );

          T := _Times.ToArray;
          P := _Period;
          H := _Head;
          E := _Head + T[ High( T ) ];
          S := ScreenOpen( FormToHWND( _Form ) );  // 終わりにも、画面が使えたか（始めは、使えるときだけ測り始める）

          _Load.Await( E, procedure begin Done_( TMotionPace.Create( T, P, _Load.Trace( H, E ), S ) ) end );
     end;
end;

procedure TMotionProbe.Ended;
var
   F :TProc;
begin
     // 終わりの処理は、ここが持ったまま呼ぶ（呼んでいる最中に、手放さない）
     F := _Finish;

     Leave;

     F();
end;

// 測るために借りた・作ったものを、戻す・手放す
procedure TMotionProbe.Leave;
begin
     _StepsN := 0;
     _Step   := nil;
     _Finish := nil;
end;

//------------------------------------------------------------------------------

// 画面を使えなければ、測らずに、無効な結果（更新 0・画面が使えなかった）を、後に回して知らせる
procedure TMotionProbe.PaceIn( const StepsN_:Integer; const Until_:Double; const Step_:TMotionStep; const Done_:TProc<TMotionPace> );
var
   P :Double;
   L :IInterface;
begin
     P := ScreenPeriod;

     if not ScreenOpen( FormToHWND( _Form ) ) then
     begin
          L := _Life;

          TThread.ForceQueue( nil, procedure begin if TMotionLife( L ).Alive then Done_( TMotionPace.Create( [ 0, 0 ], P, Default( TLoadTrace ), False ) ) end );

          Exit;
     end;

     Start( StepsN_, Until_, Step_ );

     _Period := P;

     Watch( Done_ );
end;

// 取る間、フォームを、前に出す（ほかの窓に隠れていると、その窓が写る）。窓を作り直さない手段（SetForegroundWindow・
// BringWindowToTop）で行う。測る部品は、測る相手の窓を作り直さない：作った時の窓（HWND）に結び付いた中身（埋め込みのページの
// 親・DirectComposition の描く先）を持つ窓は、作り直しに耐えず、その後の描画で落ちる（FormStyle を StayOnTop に替えると、
// FMX は窓を作り直す）。前に出せなかった（前に出す権利が無い）・後からかぶさられたときは、コマごとの確かめ（TMotionGrab.Exposed）
// で、その測定が無効になる
procedure TMotionProbe.Lift;
var
   W :HWND;
begin
     W := FormToHWND( _Form );

     SetForegroundWindow( W );
     BringWindowToTop( W );
end;
// 画面を使えなければ、測らずに、無効な結果（コマ 0・画面が使えなかった）を、後に回して知らせる
procedure TMotionProbe.ShotsIn( const StepsN_:Integer; const Until_:Double; const Step_:TMotionStep; const Area_:TRect; const Judge_:TMotionJudge; const Done_:TProc<TMotionShots> );
var
   L :IInterface;
begin
     if Area_.IsEmpty then raise EArgumentException.Create( '写し取る範囲が、空' );

     if not ScreenOpen( FormToHWND( _Form ) ) then
     begin
          L := _Life;

          TThread.ForceQueue( nil, procedure begin if TMotionLife( L ).Alive then Done_( TMotionShots.Create( 0, 0, 0, 0, 0, False ) ) end );

          Exit;
     end;

     Lift;

     Start( StepsN_, Until_, Step_ );

     _Grab := TMotionGrab.Create( FormToHWND( _Form ), Area_, Judge_ );

     _Finish := procedure
     var
        R :TMotionShots;
        G :TMotionGrab;
     begin
          G     := TMotionGrab( _Grab );
          _Grab := nil;

          G.Terminate;
          G.WaitFor;

          R := TMotionShots.Create( G.FramesN, G.BadsN, G.MissN, G.HidesN, _Watch.Elapsed.TotalMilliseconds, ScreenOpen( FormToHWND( _Form ) ) );

          G.Free;

          Done_( R );
     end;
end;

// 画面に出して測る長さ（秒）を確かめる。0 より長く、10 秒以下（画面に出す試験は、利用者の画面を占めるので短く保つ。
// 1 つの操作は 1〜2 秒：画面の更新で百数十回あれば、引っかかりの割合は決まる）。歩の数を、秒として渡す取り違えも、ここで止まる
class function TMotionProbe.Seconds( const Seconds_:Double ) :Double;
begin
     if not ( ( Seconds_ > 0 ) and ( Seconds_ <= 10 ) ) then raise EArgumentOutOfRangeException.CreateFmt( '測る長さは、0 より長く 10 秒以下：%g', [ Seconds_ ] );

     Result := Seconds_;
end;

////////////////////////////////////////////////////////////////////// E V E N T

procedure TMotionProbe.FormPaint( Sender_:TObject; Canvas_:TCanvas; const ARect_:TRectF );
begin
     _Times.Add( _Watch.Elapsed.TotalMilliseconds );

     if Assigned( _OnPaint ) then _OnPaint( Sender_, Canvas_, ARect_ );
end;

// Drift の 1 刻み：次の歩を行う。歩が済んでいれば、終わる
procedure TMotionProbe.TimerTick( Sender_:TObject );
begin
     if _Next < _StepsN then
     begin
          _Step( _Next );

          Inc( _Next );
     end
     else
     begin
          _Timer.Enabled := False;

          Ended;
     end;
end;

//&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&& public

constructor TMotionProbe.Create( const Form_:TCustomForm );
begin
     inherited Create;

     TMotionLock.Default.Acquire;  // 窓を動かして測る試験を、機械の上で 1 つずつにする（放すのは、プログラムの終わり）

     _Load  := TLoad.Create;
     _Form  := Form_;
     _Times := TList<Double>.Create;
     _Life  := TMotionLife.Create;

     TMotionLife( _Life ).Alive := True;

     _Timer := TTimer.Create( nil );
     _Timer.Enabled := False;
     _Timer.OnTimer := TimerTick;
end;

destructor TMotionProbe.Destroy;
begin
     // 後に回した歩を、動かなくする。測っている途中なら、借りたものを戻す
     TMotionLife( _Life ).Alive := False;

     _Load.Free;  // 負荷を取り終えるのを待っている知らせも、取り除かれる

     _Timer.Free;

     if Assigned( _Grab ) then
     begin
          _Grab.Terminate;
          _Grab.WaitFor;
          _Grab.Free;
     end
     else
     if _StepsN > 0 then _Form.OnPaint := _OnPaint;

     _Times.Free;

     inherited;
end;

//////////////////////////////////////////////////////////////////// M E T H O D

procedure TMotionProbe.Pace( const StepsN_:Integer; const Step_:TMotionStep; const Done_:TProc<TMotionPace> );
begin
     PaceIn( StepsN_, Infinity, Step_, Done_ );
end;

procedure TMotionProbe.PaceFor( const Seconds_:Double; const Step_:TMotionStep; const Done_:TProc<TMotionPace> );
begin
     PaceIn( MaxInt, Seconds( Seconds_ ) * 1000, Step_, Done_ );
end;
procedure TMotionProbe.Drift( const StepsN_,Gap_:Integer; const Step_:TMotionStep; const Done_:TProc<TMotionPace> );
var
   P :Double;
begin
     if Gap_ < 1 then raise EArgumentOutOfRangeException.Create( '歩の間は、1 ミリ秒以上' );

     P := ScreenPeriod;

     Begins( StepsN_, Infinity, Step_ );

     _Period := P;

     Watch( Done_ );

     _Next := 0;

     _Timer.Interval := Gap_;
     _Timer.Enabled  := True;
end;

procedure TMotionProbe.Shots( const StepsN_:Integer; const Step_:TMotionStep; const Area_:TRect; const Judge_:TMotionJudge; const Done_:TProc<TMotionShots> );
begin
     ShotsIn( StepsN_, Infinity, Step_, Area_, Judge_, Done_ );
end;

procedure TMotionProbe.ShotsFor( const Seconds_:Double; const Step_:TMotionStep; const Area_:TRect; const Judge_:TMotionJudge; const Done_:TProc<TMotionShots> );
begin
     ShotsIn( MaxInt, Seconds( Seconds_ ) * 1000, Step_, Area_, Judge_, Done_ );
end;
//------------------------------------------------------------------------------

class procedure TMotionProbe.Versus( const App_,Base_:TCustomForm; const Step_:TMotionFormStep; const Done_:TProc<TMotionVersus> );
begin
     Apart( App_, Base_ );

     PaceRounds( App_, Base_, Step_, [], procedure( R_:TArray<TMotionPace> )
     var
        A, B :TArray<TMotionPace>;
        I :Integer;
     begin
          SetLength( A, TMotionVersus.ROUNDS );
          SetLength( B, TMotionVersus.ROUNDS );
          for I := 0 to TMotionVersus.ROUNDS - 1 do
          begin
               A[ I ] := R_[ 2 * I     ];
               B[ I ] := R_[ 2 * I + 1 ];
          end;

          Done_( TMotionVersus.Create( A, B ) );
     end );
end;

class procedure TMotionProbe.ShotsVersus( const App_,Base_:TCustomForm; const Step_:TMotionFormStep; const Area_:TRect; const Judge_:TMotionJudge; const Done_:TProc<TMotionShotsVersus> );
begin
     Apart( App_, Base_ );

     ShotsRounds( App_, Base_, Step_, Area_, Judge_, [], procedure( R_:TArray<TMotionShots> )
     var
        A, B :TArray<TMotionShots>;
        I :Integer;
     begin
          SetLength( A, TMotionVersus.ROUNDS );
          SetLength( B, TMotionVersus.ROUNDS );
          for I := 0 to TMotionVersus.ROUNDS - 1 do
          begin
               A[ I ] := R_[ 2 * I     ];
               B[ I ] := R_[ 2 * I + 1 ];
          end;

          Done_( TMotionShotsVersus.Create( A, B ) );
     end );
end;
// かぶさりの確かめ：測る窓の見える枠の内の点は、測る窓そのものが、いちばん上でなければならない。枠の外の点（窓の端を、後ろの板の色で
// 見つける試験は、範囲を窓の外まで伸ばす）は、測る窓か、測っているのと同じプロセスの窓（試験が出している後ろの板）なら、よい。
// ほかのプロセスの窓が、どの点でもいちばん上なら、かぶさった。範囲と枠が交わる所の真ん中も見る（四隅と真ん中が、どれも枠の外でも、
// 窓の中身が隠れていないことを確かめる）。交わらなければ、測る窓は写らない
class function TMotionProbe.Exposed( const Area_,Frame_:TRect; const Top_:TMotionTop ) :Boolean;
var
   X :TRect;
   Q :array [ 0..5 ] of TPoint;
   I :Integer;
   S :TMotionSpot;
begin
     X := TRect.Intersect( Area_, Frame_ );

     if X.IsEmpty then Exit( False );

     Q[ 0 ] := TPoint.Create( Area_.Left     , Area_.Top        );
     Q[ 1 ] := TPoint.Create( Area_.Right - 1, Area_.Top        );
     Q[ 2 ] := TPoint.Create( Area_.Left     , Area_.Bottom - 1 );
     Q[ 3 ] := TPoint.Create( Area_.Right - 1, Area_.Bottom - 1 );
     Q[ 4 ] := Area_.CenterPoint;
     Q[ 5 ] := X.CenterPoint;

     for I := 0 to 5 do
     begin
          S := Top_( Q[ I ] );

          if Frame_.Contains( Q[ I ] ) then
          begin
               if S <> msOwn then Exit( False );
          end
          else
          if S = msOther then Exit( False );
     end;

     Result := True;
end;
class function TMotionProbe.ScreenOpen( const Wnd_:HWND ) :Boolean;
var
   D :HDESK;
   C :HDC;
   P :TPoint;
begin
     // 画面に鍵がかかっている間は、入力のデスクトップ（鍵の画面）を開けない
     D := OpenInputDesktop( 0, False, DESKTOP_READOBJECTS );

     if D = 0 then Exit( False );

     CloseDesktop( D );

     // 画面が切れている間は、画面の画素を読めない（CLR_INVALID）
     P := TPoint.Create( 0, 0 );
     ClientToScreen( Wnd_, P );

     C := GetDC( 0 );

     if C = 0 then Exit( False );
     try
          Result := GetPixel( C, P.X, P.Y ) <> CLR_INVALID;
     finally
          ReleaseDC( 0, C );
     end;
end;

// 素の窓を、アプリの窓と重ならない所へ移す（同じモニターの作業領域の中の、右・左・下・上の順に、収まる所）。
// 重なっていると、測っている窓の手前に、もう一方の窓がかぶさり、写し取るものと、描かれ方が変わる。同じモニターに置くのは、
// 画面の更新の周期をそろえるため。どこにも収まらなければ、測れないので、例外。
// 重なりと置き場は、見える枠（DWMWA_EXTENDED_FRAME_BOUNDS）で比べる：GetWindowRect の外枠は、見えない縁（窓の大きさを変えるための
// 掴み代）を含むので、作業領域を半分ずつに並べた 2 つの窓でも、重なって見える。
// 座標は、この間だけ、この実行スレッドを、モニターごとの DPI を知る扱い（DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2）にして、
// 物理の画素にそろえる：DPI を知らないプロセスでは、見える枠は物理の画素で、外枠・作業領域・移す先は 96 DPI に換算した値で返り、
// 混ぜると、ずれる（150% の画面で、外枠の幅 640 に対し、見える枠の幅 938）
class procedure TMotionProbe.Apart( const App_,Base_:TCustomForm );
var
   C :DPI_AWARENESS_CONTEXT;
begin
     C := SetThreadDpiAwarenessContext( DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2 );
     try
          Place( App_, Base_ );
     finally
          SetThreadDpiAwarenessContext( C );
     end;
end;

//------------------------------------------------------------------------------
class procedure TMotionProbe.Settle( const Load_:TLoad; const Measure_:TMotionMeasure; const Done_:TProc<TMotionPace> );
begin
     SettleFrom( Load_, Measure_, Done_, 1 );
end;
//$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 R O U T I N E 】

initialization //############################################################### ■

finalization //################################################################# ■

     TMotionLock._Default.Free;  // 握っていれば放す（プログラムの終わりまで、握り続ける）

end. //######################################################################### ■
