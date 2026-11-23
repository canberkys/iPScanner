# iPScanner — Geliştirme yol haritası (1.3.1 sonrası)

## Bağlam
iPScanner (macOS 14.4+, SwiftUI, ~6.4k satır uygulama + CLI, 201 test) yayında. Amaç: tarama motoru, arayüz, güvenlik, performans, erişilebilirlik/yerelleştirme, CI/yayın ve dokümantasyon tarafındaki eksik ve hataları çıkarıp **önceliğe göre fazlara** ayırmak. Bulgular kod okunarak çıkarıldı. En kritik olanlar kodda tek tek doğrulandı (✔ işaretli). Uygulama derlenip çalıştırılmadı; "?" işaretliler çalışma anında test edilmeli.

Her faz ayrı bir sürüm ya da PR olarak ilerler. Tamamlanan maddeler bu dosyada işaretlenir; kanıtlar [kabul tablosuna](acceptance-1.3.0.md) eklenir.

---

## Faz 0 — Acil düzeltmeler ve güvenlik → **1.3.2 (patch)**
Kullanıcıyı yanıltan sonuçlar, veri kaybı ve güvenlik.

> **Durum (23 Kasım 2026): kodda tamamlandı, yayınlanmadı.** 217 uygulama testi ve 9 relay testi geçiyor. Ayrıntılar CHANGELOG'un `Unreleased` bölümünde.
> Planlanandan farklı yapılanlar:
> - **ARP tablosundaki host'u canlı sayma ertelendi.** macOS ARP kaydını yaklaşık 20 dakika saklıyor; ağdan ayrılmış bir cihaz bu sürede canlı görünebilir. Bunun gerçek bir ağda denenmesi gerekiyor.
> - **`Host.merged` değiştirilmedi.** Port sonuçları onun yerine "taranan portlar yeni sonucu alır, diğerleri korunur" kuralıyla birleştiriliyor.
> - **Build numarası otomatik artırılmıyor.** CI'ın repoya commit atması gerekeceği için onun yerine `scripts/check-release-version.py` koruması eklendi; uyumsuz sürüm build'i imzalamadan önce durduruyor.
> - **Relay'in günlük limiti isteğe bağlı.** Cloudflare'de `FEEDBACK_DAILY` KV binding'i tanımlanınca devreye giriyor.
>
> Uygulamada doğrulananlar (24 Kasım 2026): ⌘C davranışı, pencere bazlı menü komutları ve ⌘N, sonuç yokken pasif menü öğeleri, snapshot etiketleri onayı (Return "Not Now" seçer), ATS değişikliğinden sonra yerel ağdaki HTTP başlıkları. Testler sırasında bulunan, menü komutlarının pencereleri sürekli yeniden çizdiği %100 CPU döngüsü de düzeltildi.
>
> Elle doğrulanmayı bekleyen: fiziksel bir cihazda Wake-on-LAN.

**Tarama doğruluğu**
- ✔ TCP RST (bağlantı reddi) cihazın ayakta olduğunu gösterir, ama "ölü" sayılıyor. `PortScanner.swift:71-89` sadece `.ready` durumunu kabul ediyor, `.waiting(ECONNREFUSED)` durumunu yok sayıyor. ICMP'yi engelleyen yazıcı ve IoT cihazları bu yüzden listede görünmüyor. Çözüm: probe "açık / reddedildi / zaman aşımı" ayrımı yapsın; `tcpFallback` (`NetworkScanner.swift:214`) reddedilen bağlantıyı da canlı saysın.
- ARP tablosunda tam kaydı olan host da canlı kabul edilsin (`NetworkScanner.swift:97-110`).
- ✔ `/sbin/ping` başlatılamazsa hata sessizce "ölü host" olarak dönüyor (`NetworkScanner.swift:182-190`). Bu durumda bir uyarı olayı yayınlansın; CLI de 2 koduyla çıksın.
- Fallback RTT değeri ilk açılan porta göre ölçülsün, tüm portların bitmesi beklenmesin (`NetworkScanner.swift:215`).

**Veri kaybı ve durum hataları**
- ✔ Port taraması önceki sonucun üzerine yazıyor (`ScanController.swift:428`). Önceki taramada bulunan 22 numaralı port, Web preset taramasından sonra kayboluyor. Sonuçlar birleştirilmeli (merge) ya da preset bazında tutulmalı. Ayrıca `Host.merged` portları boşaltamıyor (`Host.swift:75`).
- Başkasının `.ipscan.json` dosyası açılınca içindeki etiketler kalıcı etiketlere sessizce karışıyor (`ScanController.swift:571-574`). Bunun yerine "İçe aktar?" onayı sorulsun.
- Refresh sırasında ARP cevap vermezse MAC değeri nil oluyor ve etiket kayboluyor (`ScanController.swift:631`, `:166`).
- `PersistedStore` bozuk veriyi sessizce boş sayıyor, ardından ilk kayıtta mevcut veriyi siliyor (`PersistedStore.swift:23,35-43`). Kayıttan önce yedek alınsın ve bir uyarı gösterilsin.
- Snapshot dosyasındaki `version` alanı kontrol edilmiyor (`ScanSnapshot.swift:83`).
- İçe aktarılmış hedef dosyasıyla yapılan taramalarda snapshot yanlış aralığı kaydediyor (`ScanController.swift:513`).

**Güvenlik**
- ✔ IPv4 doğrulaması kanonik değil (`ScanRange.swift:99-108`). `1.2..3.4`, `+1.2.3.4` ve `010.0.0.1` kabul ediliyor. Sekizlik (octal) yazım tarayıcıda veya ssh'ta farklı bir hosta gidebilir. Snapshot → shell akışı bu doğrulamaya güveniyor. Her okteti tam olarak `0|[1-9]\d{0,2}` desenine bağla.
- ✔ CSV injection: `=`, `+`, `-`, `@` ile başlayan değerler etkisizleştirilmiyor (`ExportService.swift:133`). HTTP başlığı cihazın kendisinden geliyor, yani güvenilmez veri.
- HTTP banner isteği yönlendirmeleri takip ediyor (`BannerProbe.swift:44`). Yerel ağdaki bir cihaz isteği internete yönlendirebiliyor. Yalnızca aynı yerel hosta yapılan yönlendirmeler izlensin.
- `NSAllowsArbitraryLoads: true` (`project.yml:59`) daraltılmalı; ilk deneme `NSAllowsLocalNetworking`. Sonrasında banner alma işlemi test edilmeli (?).
- HostActions'ın oluşturduğu `.command` dosyaları Caches klasöründe birikiyor (`HostActions.swift:103-124`); temizlensin.
- Feedback relay: `@mention`, link ve görsel temizliği, günlük üst limit, issue etiketi (`feedback-relay/src/index.js:33`).

**Bozuk özellikler**
- ✔ Wake-on-LAN'da `allowLocalEndpointReuse`, `SO_BROADCAST` yerine geçmiyor; ilgili satırlar hiçbir işe yaramıyor (`WakeOnLAN.swift:17-21`). BSD UDP soketi + `SO_BROADCAST` + alt ağa yönelik broadcast seçeneği eklenecek.
- ✔ Gizli ⌘C butonu (`ScanToolbar.swift:114`), arama ve aralık alanlarındaki metin kopyalamayı engelliyor olabilir (?). Bu komut `CommandGroup(replacing: .pasteboard)` ile yalnızca tablo odaktayken çalışacak şekilde taşınsın.
- ✔ Menü komutları NotificationCenter üzerinden yayılıyor (`iPScannerApp.swift:81-117`), bu yüzden ⌘R tüm pencerelerde aynı anda çalışıyor. `.newItem` grubunun yerine geçildiği için ⌘N (Yeni Pencere) de kayboldu.
- NetBIOS bağlantısı hata durumunda kapatılmıyor ve iptal desteği yok (`NetBIOSResolver.swift:18-55`).

**Yayın güvenliği**
- Build numarası (`CURRENT_PROJECT_VERSION: "4"`, `project.yml:25`) elle güncelleniyor. Güncellenmesi unutulursa Sparkle güncellemeyi kimseye sunmaz. CI build numarasını otomatik artırsın, tag ile `project.yml` sürümünü de karşılaştırsın.

---

## Faz 1 — Performans ve mimari → **1.4.0**
Büyük ağlarda (/16) donma ve uzun süreler; bakım kolaylığı.

- ✔ `filteredHosts` her okunuşta tüm listeyi filtreleyip sıralıyor (`ScanController.swift:119-148`). Bir redraw'da yaklaşık 4 kez okunuyor ve 0.1 sn'lik zamanlayıcı (`:306`) tüm ContentView'i yeniden çiziyor. Sonuç `@Published` bir önbellekte tutulsun ve yalnızca host, filtre, arama veya sıralama değişince yeniden hesaplansın.
- Host ekleme işlemi `hosts.firstIndex` kullandığı için O(n²) (`ScanController.swift:681`). Mevcut `hostByIp` yanına bir id→index sözlüğü eklenmeli.
- Etiket araması her satırda tüm anahtarları sıralıyor (`MACAddress.swift:22`). Satır başına `DeviceClassifier` çağrısı da yapılıyor (`HostTable.swift:40,45`). Bu sonuçlar host başına önbelleğe alınsın.
- Ping: her host için ayrı bir `/sbin/ping` süreci başlatılıyor ve GCD thread'i bloklanıyor (`NetworkScanner.swift:163-211`). Yerine ayrıcalık gerektirmeyen `SOCK_DGRAM/IPPROTO_ICMP` soketi kullanılsın. Eşzamanlılık değeri (sabit 32) ayarlanabilir olsun. Boş bir /16 taraması bugün yaklaşık 44 dakika sürüyor.
- DNS zaman aşımında `getnameinfo` thread'leri birikiyor (`DNSResolver.swift:20-34`). Eşzamanlılık bir semaphore ile sınırlansın.
- CLI ve GUI ayrı port/banner döngüleri kullanıyor ve bu ikisi birbirinden ayrışmış durumda (`cli/EntryPoint.swift:167-205` ve `ScanController.swift:410-480`). İkisi `Services` altında ortak bir `EnrichmentPipeline` kullansın; CLI'daki sınırsız banner eşzamanlılığı da böylece düzelir.
- ContentView tek dosyada 30+ state tutuyor ve `Views/*` dosyaları yalnızca extension. Toolbar, tablo, durum çubuğu ve kenar çubuğu kendi state'ine sahip ayrı View'lara bölünsün. Komutlar `@FocusedValue`/`focusedSceneValue` ile pencere bazlı çalışsın; menü öğeleri duruma göre devre dışı kalsın (sonuç yoksa Export ve Save gibi).
- `SWIFT_STRICT_CONCURRENCY: complete` ayarına geçilip Swift 6 için hazırlık yapılsın. Gereksiz `@unchecked Sendable` kaldırılsın (`ScanEvent.swift:42`).
- Ölü kod temizliği: `UpdateChecker` (yalnızca `currentVersion` kullanılıyor), `iPScannerCommandCheckForUpdates`, `cancelPortScan`, `ParseError.noTargets`, `OUILookup.parseMAL`/`parseSubBlock`, WoL'deki boş satırlar.
- Timeout, port ve eşzamanlılık sabitleri tek bir `ScanTuning` yapısında toplansın (Faz 2'deki Ayarlar ekranına zemin olur).

---

## Faz 2 — Görünüm, UX, erişilebilirlik, yerelleştirme → **1.5.0**

**Tablo ve etkileşim**
- ✔ Yalnızca IP sütunu sıralanabiliyor (`HostTable.swift:39`). Hostname, MAC, vendor, RTT, port ve etiket sütunlarına da sıralama eklensin. Sütun gizleme/gösterme özelliği gelsin; NetBIOS adı, workgroup ve mDNS servisleri için yeni sütunlar açılsın.
- Çift tıklama her zaman `http://ip` adresini açıyor (`HostTable.swift:145`). Bunun yerine Device Details açılsın, ya da port 80 kapalıysa HTTP seçeneği gösterilmesin.
- Otomatik yeniden tarama tabloyu ve seçimi siliyor, açık inspector da kapanıyor (`ScanController.swift:294`). Tablo yerinde güncellensin.
- Manuel port taramasından sonra durum metni bozuluyor ("N of N", `ScanController.swift:397`).
- Pencere 1050 pt'nin altına küçülünce inspector aniden sheet'e dönüşüyor (`ContentView.swift:75`).
- Export işlemi yalnızca filtrelenmiş satırları alıyor ama bunu kullanıcıya söylemiyor. Ayrıca metin raporundaki "Alive" sayısı satırlarla tutmuyor (`ContentView.swift:603,692`).
- Kısayollar standart değil: ⌘S CSV export ediyor, ⌘F yok (`searchFieldFocused` tanımlı ama hiç kullanılmıyor), Return tuşu arama alanındayken tarama başlatıyor olabilir (?). Standart macOS kısayollarına geçilsin.
- Toolbar yerel (native) bir toolbar olsun: özelleştirilebilsin ve birleşik başlık çubuğu kullanılsın.
- Kayıtlı aralıklar listesinde klavye seçimi, yeniden sıralama ve "Tara" aksiyonu olsun (`ContentView.swift:264`).
- Kaybolan cihazlar listesi rastgele sırada geliyor ve aynı IP iki kez görünürse ID çakışıyor (`SnapshotDiff.swift:18`, `ContentView.swift:893`). MAC değeri yoksa aynı cihaz hem "yeni" hem "kayıp" görünüyor; IP değişimi de raporlanmıyor (`SnapshotDiff.swift:28-75`).
- Sayfa başlıklarındaki satır sonları temizlensin, Latin-1 ve HTML entity çözümleme eklensin (`BannerProbe.swift:37,59-67`).

**Erişilebilirlik**
- Durum yalnızca renkle gösteriliyor ve "dead" ile "scanning" aynı gri. Şekil veya ikon farkı eklensin.
- İkon butonlara, sparkline'a ve inspector aksiyonlarına accessibility label/hint eklensin.
- Sabit 12 pt font kaldırılsın (`ScanStatusBar.swift:79`).
- Açık temada sarı "changed" metninin kontrastı düşük.
- Kabul tablosunda hâlâ açık olan VoiceOver ve klavye matrisi ile 800/960/1280 genişlik × tema matrisi tamamlansın.

**Yerelleştirme (Türkçe öncelikli)**
- Yerelleştirme altyapısı yok: String Catalog (`Localizable.xcstrings`) eklensin, `CFBundleLocalizations` listesine `tr` girsin. `rawValue` değerleri ekranda gösterilmesin. Feedback issue başlığındaki önek İngilizce kalsın (`FeedbackDraft.swift:26`). Çoğul ifadeler katalogdaki plural kurallarıyla yazılsın.
- Arama aksan ve büyük/küçük harf duyarsız olsun: `localizedStandardContains` ile "kilic" araması "Kılıç" ile eşleşsin.
- CSV'ye UTF-8 BOM eklensin ve `;` ayraç seçeneği gelsin; Türkçe Excel bugün dosyayı tek sütun olarak açıyor. DateFormatter'larda `en_US_POSIX` kullanılsın.
- Yardım metnindeki "What's New" bölümü 1.3.0'da kalmış (`ProductHelpView.swift:13`).

**Ayarlar**
- Ayarlara şunlar eklensin: timeout, eşzamanlılık, varsayılan otomatik tarama, varsayılan sütunlar, unresponsive host'ları gösterme, export varsayılanları.

---

## Faz 3 — Yeni özellikler → **1.6 / 2.0**
Kullanıcıya en çok değer katandan aza doğru:
1. **Cihaz geçmişi:** first/last seen bilgisi ve MAC↔IP geçmişi, küçük bir yerel depoda (SwiftData veya SQLite) tutulur. Otomatik taramadan sonra veriler kaybolmaz.
2. **Yeni veya kaybolan cihaz bildirimleri** (`UserNotifications`), geçmiş özelliğinin üzerine kurulur.
3. **Menü çubuğu modu** (`MenuBarExtra`): arka planda periyodik tarama ve özet.
4. **Keşif genişletmeleri:** SSDP/UPnP, mDNS adlarının hostname olarak kullanılması (bugün yalnızca GUI'de var), isteğe bağlı SNMP; banner portlarına 8080 ve 8443 eklenmesi; sınıflandırıcıya TTL, NetBIOS, mDNS ve gateway sinyalleri.
5. **Hedef girişi:** `192.168.1.10-50` kısa yazımı, hostname hedefleri, arayüz seçimi ve route tabanlı varsayılan alt ağ (bugün `en0` sabit). VPN `utun` desteği; CGNAT/Tailscale (100.64/10) için TLS izni.
6. **IPv6** (NDP, link-local): büyük bir iş; model katmanında `IPv4` tipinin genelleştirilmesini gerektirir.
7. **Export/Import:** HTML rapor, Nmap uyumlu XML, CSV import; etiket ve kayıtlı aralıkların yedeklenip geri yüklenmesi.
8. **Sürükle-bırak:** hedef dosyası veya IP listesi pencereye bırakılabilsin.
9. **CLI:** `--timeout`, `--concurrency`, `--no-tcp-fallback`, `--include-dead`, `--version`, `--verbose`, kısa bayraklar, `--flag=value` yazımı, `--input -` ile stdin, birden fazla hedef argümanı, SIGINT ile o ana kadarki kısmi sonucun yazılması. Hata mesajları ve kullanım metni stderr'e gitsin, `--quiet` gerçekten sessiz olsun. Range ile `--input` birlikte verilince uyarı versin (`EntryPoint.swift:18,137,142`).

---

## Faz 4 — CI/CD, test ve topluluk (diğer fazlara paralel)

**CI** (`.github/workflows/ci.yml`, `release.yml`)
- `permissions` bloğu eklensin (en az yetki), `concurrency` grubu tanımlansın, action'lar SHA ile sabitlensin (özellikle signing secret'larının bulunduğu job'daki `softprops/action-gh-release`).
- Xcode sürümü sabitlensin, xcodegen sürümü pinlensin, macOS 14 runner matrisi eklensin, SPM ve DerivedData cache'i kurulsun, çift derleme kaldırılsın.
- xcresult artifact'ı ve coverage raporu alınsın; `feedback-relay` için `npm test` CI'a eklensin.
- SwiftLint/SwiftFormat, CodeQL, dependency-review ve Dependabot (Sparkle, npm, actions) eklensin. `Package.resolved` commit edilsin (şu an `.gitignore`'da).

**Yayın**
- Appcast'in `main`'e alınması otomatikleşsin (bugün elle yapılıyor).
- Homebrew cask eklensin.
- IEEE OUI verisi zamanlanmış bir job ile güncellensin.
- `workflow_dispatch` varsayılanı ve `build-dmg.sh` içindeki sabit 1.3.1 değeri kaldırılsın.

**Test**
- Testi olmayan modüller kapsansın: HostActions'taki shell guard, BannerProbe'un trust/redirect davranışı, CLI argüman ve çıktıları, NetworkInterface, PingMonitor, RescanInterval/ScanProfile.
- UI test hedefi eklensin (temel tarama, filtre, export akışları).
- Sabit `sleep` kullanan kırılgan testler (`ScanLifecycleTests.swift:82,126`, `DiscoveryRegressionTests.swift:44`) deterministik bekleme ile yeniden yazılsın. Ağa bağımlı DNS testi izole edilsin.
- Faz 0'daki her hata için bir regresyon testi yazılsın.

**Dokümantasyon ve topluluk**
- Eklenecek dosyalar: `SECURITY.md`, `CODE_OF_CONDUCT.md`, `CODEOWNERS`.
- Eskimiş bilgiler güncellensin:
  - README'deki "190 tests" ifadesi 201 olmalı.
  - `SUPPORT.md` ve bug şablonu hâlâ 1.3.0 diyor.
  - `signing-guide-tr.md` 1.3.0'dan bahsediyor, "Codex" referansları içeriyor ve notarization yöntemi CI ile uyuşmuyor.
  - `automatic-updates.md` içindeki "vLens" referansı açıklanmalı.
  - CHANGELOG'a sürüm bağlantıları eklenmeli ve tarih tekrarı düzeltilmeli.
  - Kabul tablosu 1.3.1 için ayrı mı tutulacak, birleştirilecek mi, netleştirilmeli.
- Kabul tablosundaki açık doğrulamalar: macOS 27'de MAC erişimi (provisioning), Intel ve macOS 14.4/Sequoia üzerinde temiz açılış, fiziksel Wake-on-LAN testi, canlı Bonjour kaydının kaybolması ve ağ değişimi, Sparkle'da iptal ve kesintili kurulum senaryoları, herkese açık eski→yeni sürüm geçişi, GitHub Actions release ortamındaki imza anahtarı kurulumu.

---

## Yayın durumu (1.3.x)

[1.3.0](https://github.com/canberkys/iPScanner/releases/tag/v1.3.0) 26 Eylül 2026'da
yayınlandı. Yeni radar ikonu, Sparkle güncellemeleri, Developer ID imzası,
notarization, DMG ve checksum tamamlandı. #10'daki paketleme hatası giderildi ve
issue kapatıldı. Üçüncü taraf bağımlılığı eklememe kararı Sparkle için değiştirildi;
CLI'ye Sparkle bağımlılığı eklenmedi.

1.3.1 (28 Eylül): tarama, etiket ve karşılaştırma düzeltmeleri; yeni DMG düzeni.
201 test geçti. Gerçek 1.3.0 → 1.3.1 güncellemesini kullanıcı deneyecek.

Yayın sırası [güncelleme dağıtımı](automatic-updates.md) belgesini izler: önce imzalı dosya, ardından doğrulama ve en son appcast. Henüz denenmemiş senaryolar geçmiş sayılmaz.

---

## Önemli dosyalar
`iPScanner/Services/{NetworkScanner,PortScanner,ScanController,ExportService,BannerProbe,WakeOnLAN,NetBIOSResolver,PersistedStore,SnapshotDiff}.swift`, `iPScanner/Models/{ScanRange,Host,MACAddress}.swift`, `iPScanner/ContentView.swift`, `iPScanner/Views/{HostTable,ScanToolbar,ScanStatusBar}.swift`, `iPScanner/iPScannerApp.swift`, `cli/EntryPoint.swift`, `project.yml`, `.github/workflows/*.yml`, `feedback-relay/src/index.js`.

## Doğrulama (her faz için)
- `xcodebuild test -scheme iPScanner -destination 'platform=macOS' CODE_SIGN_IDENTITY=-`: mevcut 201 test ve yeni regresyon testleri geçmeli.
- `python3 scripts/build-vendor-db.py --check` ve `(cd feedback-relay && npm test)` geçmeli.
- Faz 0 elle kontrolleri: ICMP'yi engelleyen ama portu reddeden bir host canlı görünmeli; `010.0.0.1` içeren bir snapshot reddedilmeli; `=HYPERLINK` başlığı içeren CSV Excel'de metin olarak açılmalı; WoL fiziksel bir cihazda denenmeli; iki pencere açıkken ⌘R yalnızca aktif pencerede çalışmalı.
- Faz 1: bir /16 taramasında (veya 65k sahte hostla yapılan benchmark testinde) UI akıcı kalmalı ve süre ölçülmeli.
- Faz 2: VoiceOver ve klavye matrisi, `tr` diliyle çalıştırma, Türkçe Excel'de CSV açılışı.
- Yayın: imzalı DMG → `scripts/verify-app.sh` → Sparkle ile eski sürümden yeni sürüme geçiş.
