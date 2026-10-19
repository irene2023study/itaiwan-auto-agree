# iTaiwan自動連線

Windows 筆電連上 iTaiwan 免費 Wi‑Fi 時，自動在背景按下認證頁的「同意」，不用每次打開瀏覽器手動點選。

## 安裝

1. 下載 [`itaiwan-setup.bat`](itaiwan-setup.bat)（點進去後按右上角的下載按鈕）。
2. 雙擊執行。
3. 看到「安裝完成！」對話框就完成了。

第一次執行時，Windows 可能會跳出「Windows 已保護您的電腦」。這是因為檔案來自網路，點「其他資訊」→「仍要執行」即可。

## 運作方式

安裝後會建立一個 Windows 排程工作，每次電腦連上網路時觸發。腳本會：

1. 檢查目前連上的 Wi‑Fi 是不是 `iTaiwan`，不是就直接結束。
2. 確認是否已經能上網；如果還不行，就抓取認證頁。
3. 找到含有「同意」的表單，勾選同意選項後送出。
4. 最多重試 5 次。

整個過程不會開瀏覽器，也不會跳出視窗。

## 疑難排解

紀錄檔放在 `%LOCALAPPDATA%\iTaiwanAutoAgree`（貼到檔案總管網址列即可開啟）：

- `log.txt`：每次執行的紀錄
- `portal.html`：最後一次抓到的認證頁
- `after-submit.html`：送出同意後的回應頁

如果連上 iTaiwan 後還是不能上網，可以查看這些檔案找出原因。若認證頁改成用 JavaScript 動態送出，這個腳本可能需要調整。

## 移除

在 PowerShell 執行：

```powershell
Unregister-ScheduledTask -TaskName iTaiwanAutoAgree -Confirm:$false
```

再刪除 `%LOCALAPPDATA%\iTaiwanAutoAgree` 資料夾即可。
