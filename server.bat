@echo off
title NoTrack PS4 Server
mode con: cols=70 lines=30
setlocal enabledelayedexpansion

:: ============================================
:: NoTrack PS4 Server - DNS + HTTP Server
:: Cria um servidor local para PS4 desbloqueado
:: Redireciona PSN e Rockstar para o PC local
:: ============================================

:: Pega o IP local da máquina
for /f "tokens=2 delims=:" %%a in ('ipconfig ^| findstr /c:"IPv4" /c:"Endereço IPv4"') do (
    set "IP=%%a"
    goto :foundip
)
:foundip
set IP=%IP: =%
echo.
echo  ========================================
echo      NoTrack PS4 Server v1.0
echo  ========================================
echo.
echo  Servidor iniciado em: %IP%:80
echo.

:: Verifica se o PowerShell pode ser usado para o DNS
echo  [*] Iniciando servidor DNS na porta 53...
echo  [*] Iniciando servidor HTTP na porta 80...
echo.

:: Cria o arquivo hosts dinâmico para o servidor DNS simples
set HOSTS_FILE=%TEMP%\notrack_dns.txt
(
    echo # NoTrack PS4 DNS Redirect
    echo # PSN
    echo %IP% *.playstation.net
    echo %IP% *.psn.net
    echo %IP% *.sonyentertainmentnetwork.com
    echo %IP% *.np.ac.playstation.net
    echo %IP% *.npsp.ac.playstation.net
    echo %IP% *.np.community.playstation.net
    echo %IP% *.np.prod.ac.playstation.net
    echo %IP% *.auth.api.sony.com
    echo %IP% *.auth.np.ac.playstation.net
    echo %IP% *.grp.np.community.playstation.net
    echo %IP% *.prof.np.community.playstation.net
    echo %IP% *.ps4.np.community.playstation.net
    echo %IP% *.ps5.np.community.playstation.net
    echo %IP% *.f.np.community.playstation.net
    echo # Rockstar / GTA V
    echo %IP% *.rockstargames.com
    echo %IP% *.gta5.com
    echo %IP% *.gtaonline.com
    echo %IP% prod.ros.rockstargames.com
    echo %IP% prod.cyc.rockstargames.com
    echo %IP% prod.cloud.rockstargames.com
    echo %IP% prod.stun.rockstargames.com
    echo %IP% prod.gta5.rockstargames.com
    echo %IP% prod.telemetry.rockstargames.com
    echo %IP% prod.socialclub.rockstargames.com
    echo %IP% prod.matchmaking.rockstargames.com
    echo %IP% prod.game.rockstargames.com
    echo %IP% prod.vst.rockstargames.com
    echo %IP% prod.storage.rockstargames.com
    echo # GTA V Online Services
    echo %IP% gta5-online.rockstargames.com
    echo %IP% online.rockstargames.com
    echo %IP% socialclub.rockstargames.com
    echo %IP% cloud.rockstargames.com
) > %HOSTS_FILE%

:: Inicia o servidor HTTP + DNS em PowerShell (single instance)
start "NoTrack PS4 Server" powershell -NoExit -Command ^
    "$ip = '%IP%';" ^
    "Write-Host 'NoTrack PS4 Server - HTTP + DNS' -ForegroundColor Cyan;" ^
    "Write-Host '====================================' -ForegroundColor Cyan;" ^
    "Write-Host '';" ^
    "Write-Host ('IP do Servidor: ' + $ip) -ForegroundColor Green;" ^
    "Write-Host 'Porta HTTP: 80' -ForegroundColor Green;" ^
    "Write-Host 'Porta DNS: 53' -ForegroundColor Green;" ^
    "Write-Host '';" ^
    "Write-Host 'PSN e Rockstar Games estao sendo redirecionados para:' -ForegroundColor Yellow;" ^
    "Write-Host ('http://' + $ip + ':80') -ForegroundColor White;" ^
    "Write-Host '';" ^
    "Write-Host 'Pressione CTRL+C para parar o servidor' -ForegroundColor Gray;" ^
    "Write-Host '';" ^
    " " ^
    "# === Servidor HTTP ===;" ^
    "$httpListener = New-Object System.Net.HttpListener;" ^
    "$httpListener.Prefixes.Add('http://+:80/');" ^
    "$httpListener.Start();" ^
    "Write-Host '[HTTP] Servidor rodando na porta 80...' -ForegroundColor Cyan;" ^
    " " ^
    "# === Servidor DNS UDP ===;" ^
    "$dnsSocket = New-Object System.Net.Sockets.UdpClient(53);" ^
    "Write-Host '[DNS] Servidor rodando na porta 53...' -ForegroundColor Cyan;" ^
    "Write-Host '';" ^
    " " ^
    "# Loop principal - atende HTTP e DNS em paralelo;" ^
    "while ($true) {" ^
    "    # HTTP - aceita request assincrono;" ^
    "    $httpTask = $httpListener.GetContextAsync();" ^
    "    # DNS - recebe pacote assincrono;" ^
    "    $dnsTask = $dnsSocket.ReceiveAsync();" ^
    "    " ^
    "    $completed = [System.Threading.Tasks.Task]::WaitAny($httpTask, $dnsTask, 1000);" ^
    "    " ^
    "    if ($completed -eq 0 -and $httpTask.IsCompleted) {" ^
    "        $context = $httpTask.Result;" ^
    "        $request = $context.Request;" ^
    "        $response = $context.Response;" ^
    "        $url = $request.Url;" ^
    "        Write-Host ('[HTTP] ' + $request.RemoteEndPoint + ' -> ' + $url.Host + $url.LocalPath) -ForegroundColor DarkGray;" ^
    "        " ^
    "        # Retorna JSON de sucesso simulando PSN/Rockstar;" ^
    "        $respJson = @'{'@;" ^
    "        $respJson += '\"status\": \"online\",';" ^
    "        $respJson += '\"services\": {';";" ^
    "        $respJson += '  \"psn\": true,';" ^
    "        $respJson += '  \"rockstar\": true,';" ^
    "        $respJson += '  \"gta5\": true';;" ^
    "        $respJson += '},';" ^
    "        $respJson += '\"server\": \"NoTrack PS4 Server v1.0\",';" ^
    "        $respJson += '\"ip\": \"' + $ip + '\"';" ^
    "        $respJson += '}@';" ^
    "        $buffer = [System.Text.Encoding]::UTF8.GetBytes($respJson);" ^
    "        $response.ContentType = 'application/json';" ^
    "        $response.Headers.Add('Access-Control-Allow-Origin', '*');" ^
    "        $response.OutputStream.Write($buffer, 0, $buffer.Length);" ^
    "        $response.Close();" ^
    "    }" ^
    "    " ^
    "    if ($completed -eq 1 -and $dnsTask.IsCompleted) {" ^
    "        $dnsResult = $dnsTask.Result;" ^
    "        $remoteEp = $dnsResult.RemoteEndPoint;" ^
    "        $data = $dnsResult.Buffer;" ^
    "        Write-Host ('[DNS] Query de ' + $remoteEp.Address) -ForegroundColor DarkGray;" ^
    "        " ^
    "        # Monta resposta DNS simples - sempre responde com o IP do servidor;" ^
    "        $responsePkt = New-Object byte[] ($data.Length + 4);" ^
    "        [Array]::Copy($data, $responsePkt, $data.Length);" ^
    "        $responsePkt[2] = 0x81;  # Flags: resposta padrao;" ^
    "        $responsePkt[3] = 0x80;  # No error;" ^
    "        $responsePkt[7] = 1;     # 1 resposta;" ^
    "        " ^
    "        # Adiciona resposta A record com o IP do servidor;" ^
    "        $pos = $data.Length;" ^
    "        $responsePkt[$pos] = 0xC0; $pos++;" ^
    "        $responsePkt[$pos] = 0x0C; $pos++;  # Pointer ao nome;" ^
    "        $responsePkt[$pos] = 0x00; $pos++;  # Type A;" ^
    "        $responsePkt[$pos] = 0x01; $pos++;" ^
    "        $responsePkt[$pos] = 0x00; $pos++;  # Class IN;" ^
    "        $responsePkt[$pos] = 0x01; $pos++;" ^
    "        " ^
    "        # TTL = 60 segundos;" ^
    "        $responsePkt[$pos] = 0x00; $pos++;" ^
    "        $responsePkt[$pos] = 0x00; $pos++;" ^
    "        $responsePkt[$pos] = 0x00; $pos++;" ^
    "        $responsePkt[$pos] = 0x3C; $pos++;" ^
    "        " ^
    "        # Data length = 4 bytes (IPv4);" ^
    "        $responsePkt[$pos] = 0x00; $pos++;" ^
    "        $responsePkt[$pos] = 0x04; $pos++;" ^
    "        " ^
    "        # IP do servidor em bytes;" ^
    "        $octets = $ip.Split('.');" ^
    "        foreach ($octet in $octets) {" ^
    "            $responsePkt[$pos] = [byte][int]$octet; $pos++;" ^
    "        }" ^
    "        " ^
    "        $dnsSocket.Send($responsePkt, $pos, $remoteEp) | Out-Null;" ^
    "    }" ^
    "}"

echo.
echo  ========================================
echo      Servidor NoTrack iniciado!
echo  ========================================
echo.
echo  Configure seu PS4 com:
echo   - DNS: %IP%
echo   - Proxy: %IP%:80
echo.
echo  Configure o plugin GoldHEN para:
echo   - Server IP: %IP%
echo.
echo  Pressione qualquer tecla para abrir o painel...
pause >nul

:: Abre o painel no navegador
start http://%IP%:80/

echo.
echo  Painel aberto no navegador.
echo  Pressione CTRL+C na janela PowerShell para parar.
echo.
pause