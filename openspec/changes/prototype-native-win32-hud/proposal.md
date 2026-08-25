## Why

褰撳墠 Windows 鐗堝熀浜?.NET 10 WPF锛岃嚜鍖呭惈鍗曟枃浠跺彂甯冪害 74.5 MB锛屾槑鏄鹃珮浜?macOS DMG锛屼笖鏍稿績 HUD 浠嶄富瑕佷緷璧栨墭绠¤繍琛屾椂銆傜幇鏈?C++/Win32 鍘熷瀷璇佹槑浜嗙郴缁?API 璺嚎鍙锛屼絾鍏舵墜宸ヨ祫婧愮敓鍛藉懆鏈熴€侀敊璇爜浼犳挱鍜屽ぇ闈㈢Н闈炲畨鍏ㄨ竟鐣屼細澧炲姞闀挎湡缁存姢鎴愭湰銆傚師鐢熷疄鐜版敼鐢?Rust 涓?Microsoft `windows-rs`锛屽湪淇濇寔 Win32 鑳藉姏鍜岃交閲忓垎鍙戠殑鍚屾椂锛岃幏寰楀唴瀛樺畨鍏ㄣ€佹樉寮忛敊璇鐞嗗拰鏇村彲缁存姢鐨勬ā鍧楄竟鐣屻€?
## What Changes

- 鏂板闈㈠悜 Windows 11 x64 鐨勫師鐢?HUD 鍘熷瀷锛屼娇鐢ㄧǔ瀹氱増 Rust銆丆argo銆乣windows` crate銆乄in32銆丏irect2D銆丏irectWrite銆乄IC銆丏WM 涓?Windows SDK 鑷甫缁勪欢锛屼笉寮曞叆绗笁鏂?UI 妗嗘灦鎴栭澶栬繍琛屾椂銆?- 灏?Windows API銆丆OM銆佸彞鏌勫拰鍥炶皟鎵€闇€鐨?`unsafe` 浠ｇ爜闄愬埗鍦?Platform銆丷ender 涓?Storage 鐨勭獎杈圭晫涓紱Core 鍜?App 缂栨帓灞傚彧浣跨敤瀹夊叏 Rust 绫诲瀷涓庢樉寮?`Result`銆?- 鍦ㄧ嫭绔嬬洰褰曞拰鐙珛鍙墽琛屾枃浠朵腑瀹炵幇涓庡綋鍓?Windows 鐗堜竴鑷寸殑鏍稿績閾捐矾锛氶€忔槑缃《 HUD銆侀粯璁ょ┛閫忋€佷氦浜掓ā寮忋€佷换鍔℃姇褰变笌鐘舵€佹帹杩涖€佹枃浠跺埛鏂般€侀€氱煡鍖哄煙鍏ュ彛銆佹祬鑹插弻椤佃缃拰鍙€夊叏灞€蹇嵎閿€?- 澶嶇敤 `%LOCALAPPDATA%\GhostPin\todos.json` 浠诲姟濂戠害锛屼絾浣跨敤鍘熷瀷涓撳睘璁剧疆鏂囦欢锛岄伩鍏嶈鐩栫幇鏈?WPF 璁剧疆锛涗笉鍚屾椂鍚姩涓ょ Windows HUD 浣滀负鍙楁敮鎸佸満鏅€?- 浜у嚭鏃犻渶 .NET銆乂isual C++ Redistributable 鎴栧悓鐩綍璧勬簮鐨勫崟鏂囦欢 Release x64 EXE锛屽苟鎶婁笉瓒呰繃 10,000,000 瀛楄妭浣滀负鍘熷瀷浣撶Н闂ㄦ銆?- 澧炲姞鍙噸澶嶇殑 Rust Release 鏋勫缓銆佽涓烘鏌ュ拰鍖呬綋銆佸惎鍔ㄦ椂闂淬€佺┖闂插唴瀛橀噰鏍凤紝褰㈡垚涓庡綋鍓?WPF 鑷寘鍚?EXE 鐨勫鐓х粨鏋滃拰淇濈暀銆佹浛鎹㈡垨缁堟鍘熷瀷鐨勫喅绛栬褰曘€?- 褰撳墠 C++ 鍘熷瀷浠呬綔涓鸿縼绉绘湡闂寸殑琛屼负鍙傝€冿紱Rust 鍘熷瀷閫氳繃楠岃瘉鍚庣Щ闄よ鏇夸唬鐨?CMake/C++ 鏋勫缓涓庢簮鐮侊紝涓嶅舰鎴?C++/Rust 娣峰悎杩愯鏃躲€?- 鏆備笉鎺ュ叆 GitHub Release锛沇indows 寮€鍙戦樁娈甸€氳繃骞冲彴鑷姩璇嗗埆鐨?`make start` 鏋勫缓骞跺惎鍔?Rust 鍘熺敓瀹㈡埛绔紝姝ｅ紡涓嬭浇涓庡彂甯冨垏鎹㈠彟琛屽鐞嗐€?- 涓嶅疄鐜拌櫄鎷熸闈㈠浐瀹氥€佺嫭鍗犲叏灞忚鐩栥€乄indows CLI銆佹彁閱掗€氱煡銆佸畨瑁呭櫒鎴栬嚜鍔ㄦ洿鏂帮紱鐧诲綍鏃跺惎鍔ㄥ睘浜庝笌 macOS 瀵归綈鐨勫鎴风璁剧疆銆?
### 宸茬‘璁ょ殑浜у搧鍐崇瓥

- 鍚庣画 Windows 鍙繚鐣?Rust 鍘熺敓瀹㈡埛绔紝WPF 浠呬綔涓鸿縼绉绘湡闂寸殑鍥為€€鍩虹嚎銆?- HUD銆佹墭鐩樸€佽缃€佸揩鎹烽敭銆佷换鍔℃帹杩涖€佹枃浠跺埛鏂板拰鐒︾偣璇箟鍧囦互 macOS 鐗堟湰涓鸿涓哄熀鍑嗭紱Windows 鍙繚鐣欏钩鍙板樊寮傘€?- 璁剧疆閲囩敤 JSON 鏂囦欢锛涜瘯鐢ㄩ樁娈靛啓鍏?`%LOCALAPPDATA%\GhostPin\native-settings.json`锛屼笌鏃?WPF 璁剧疆闅旂銆?- 瑙嗚瀵归綈 macOS 鐨勬祬鑹?GhostPin HUD锛屼笉浠ュ綋鍓?WPF 鐨勯粦鑹叉垨鐙珛瑙嗚涓虹洰鏍囥€?- `windows-rs` 鍙壙鎷?Windows API 鎶曞奖锛涗笉浣跨敤 WinUI 3銆乄indows App SDK銆乄ebView 鎴栨墭绠?UI 杩愯鏃躲€?
## Capabilities

### New Capabilities

- `native-win32-hud-prototype`: 瀹氫箟 Rust 鍘熺敓 Windows HUD 鍘熷瀷蹇呴』瑕嗙洊鐨勭獥鍙ｃ€佹覆鏌撱€佷换鍔°€佽缃€佹墭鐩樸€佸畨鍏ㄨ竟鐣屽拰鍙噺鍖栬瘎浼拌涓恒€?
### Modified Capabilities

鏃犮€?
## Impact

- 鍦?`windows-native/` 寤虹珛 Cargo 宸ョ▼銆丷ust 婧愮爜銆佽祫婧愩€佽涓烘鏌ヤ笌璇勪及鏂囨。锛涗笉淇敼鐜版湁 Swift Package 鍜?WPF solution 鐨勮繍琛屼唬鐮併€?- Windows 寮€鍙戠幆澧冮渶瑕佺ǔ瀹氱増 Rust 宸ュ叿閾俱€丆argo銆丮SVC 閾炬帴鍣ㄥ拰 Windows 11 SDK锛涘簲鐢ㄨ繍琛屾椂浠呰皟鐢ㄧ郴缁熸彁渚涚殑 Win32銆丏irect2D銆丏irectWrite銆乄IC銆丏WM銆丼hell 涓庢敞鍐岀儹閿?API銆?- 渚濊禆浠ラ攣瀹氱増鏈殑 Microsoft `windows` crate 涓轰富锛屽彧鍚敤瀹為檯浣跨敤鐨?Windows API features锛涙柊澧炰緷璧栧繀椤绘湁鏄庣‘鐢ㄩ€斿苟杩涘叆浣撶Н涓庤鍙瘉妫€鏌ャ€?- 鍘熷瀷灏嗚鍙栧苟鍦ㄤ氦浜掓帹杩涙椂鍘熷瓙鍐欏洖鐜版湁 Windows 浠诲姟鏂囦欢锛涜缃啓鍏ョ嫭绔嬫枃浠躲€傚疄鏂藉拰浜哄伐楠屾敹鏈熼棿涓嶅緱璁?WPF 涓庡師鐢?HUD 鍚屾椂鍐欏悓涓€浠诲姟鏂囦欢銆?- 鎶€鏈爤鍒囨崲浣挎棦鏈?C++ 瀹炵幇浠诲姟涓嶅啀绠椾綔 Rust 瀹屾垚椤癸紝鍥犳鏈彉鏇寸殑瀹炵幇浠诲姟鐘舵€佷粠闆堕噸鏂版牳绠椼€?- 褰撳墠鍙戝竷娴佺▼鍜岀敤鎴烽粯璁や笅杞戒繚鎸佷笉鍙橈紱鏈彉鏇村彧浜у嚭鍙瘮杈冪殑鍘熷瀷鍙婂喅绛栬瘉鎹紝涓嶇洿鎺ュ垏鎹㈡寮?Windows 瀹炵幇銆?