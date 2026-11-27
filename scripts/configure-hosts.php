<?php
declare(strict_types=1);

$apiUrl = 'http://127.0.0.1/zabbix/api_jsonrpc.php';
$secretDir = '/var/lib/zabbix-install';
$adminFile = $secretDir . '/admin-password';
$localHost = 'tenzatebou-zbx8';
$token = null;

function api(string $method, array $params): mixed {
    global $apiUrl, $token;
    $body = json_encode(['jsonrpc' => '2.0', 'method' => $method, 'params' => $params, 'id' => 1], JSON_THROW_ON_ERROR);
    $curl = curl_init($apiUrl);
    $headers = ['Content-Type: application/json-rpc'];
    if ($token !== null) {
        $headers[] = 'Authorization: Bearer ' . $token;
    }
    curl_setopt_array($curl, [
        CURLOPT_POST => true,
        CURLOPT_POSTFIELDS => $body,
        CURLOPT_HTTPHEADER => $headers,
        CURLOPT_RETURNTRANSFER => true,
        CURLOPT_TIMEOUT => 15,
    ]);
    $raw = curl_exec($curl);
    $err = curl_error($curl);
    curl_close($curl);
    if ($raw === false) {
        throw new RuntimeException("API $method: $err");
    }
    $data = json_decode($raw, true, 512, JSON_THROW_ON_ERROR);
    if (isset($data['error'])) {
        throw new RuntimeException("API $method: " . json_encode($data['error']));
    }
    if (!array_key_exists('result', $data)) {
        throw new RuntimeException("API $method: neplatna odpoved");
    }
    return $data['result'];
}

$password = is_file($adminFile) ? trim(file_get_contents($adminFile)) : 'zabbix';
$lastError = null;
for ($i = 0; $i < 30; $i++) {
    try {
        $token = api('user.login', ['username' => 'Admin', 'password' => $password]);
        break;
    } catch (Throwable $e) {
        $lastError = $e;
        sleep(2);
    }
}
if ($token === null) {
    throw $lastError ?? new RuntimeException('Zabbix API neni dostupne');
}

$groups = api('hostgroup.get', ['filter' => ['name' => ['SPOS Lab']], 'output' => ['groupid']]);
$groupId = $groups ? $groups[0]['groupid'] : api('hostgroup.create', ['name' => 'SPOS Lab'])['groupids'][0];

$templates = api('template.get', ['filter' => ['host' => ['Linux by Zabbix agent']], 'output' => ['templateid']]);
if (!$templates) {
    throw new RuntimeException('Chybi sablona Linux by Zabbix agent');
}
$templateId = $templates[0]['templateid'];

$certTemplates = api('template.get', ['filter' => ['host' => ['Website certificate by Zabbix agent 2']], 'output' => ['templateid']]);
if (!$certTemplates) {
    throw new RuntimeException('Chybi sablona Website certificate by Zabbix agent 2');
}
$certTemplateId = $certTemplates[0]['templateid'];

$hosts = api('host.get', ['filter' => ['host' => [$localHost]], 'output' => ['hostid']]);
if (!$hosts) {
    api('host.create', [
        'host' => $localHost,
        'groups' => [['groupid' => $groupId]],
        'templates' => [['templateid' => $templateId]],
        'interfaces' => [[
            'type' => 1,
            'main' => 1,
            'useip' => 1,
            'ip' => '127.0.0.1',
            'dns' => '',
            'port' => '10050',
        ]],
    ]);
}

$existingCert = api('host.get', ['filter' => ['host' => ['sposdk.cz']], 'output' => ['hostid']]);
if (!$existingCert) {
    api('configuration.import', [
        'format' => 'yaml',
        'source' => file_get_contents('/tmp/sposdk.cz_hosts.yaml'),
        'rules' => [
            'host_groups' => ['createMissing' => true, 'updateExisting' => true],
            'hosts' => ['createMissing' => true, 'updateExisting' => true],
            'templateLinkage' => ['createMissing' => true, 'updateExisting' => true],
        ],
    ]);
}

$certHost = api('host.get', [
    'filter' => ['host' => ['sposdk.cz']],
    'output' => ['hostid'],
    'selectInterfaces' => ['interfaceid'],
]);
if ($certHost) {
    $update = [
        'hostid' => $certHost[0]['hostid'],
        'templates' => [['templateid' => $certTemplateId]],
    ];
    if (empty($certHost[0]['interfaces'])) {
        $update['interfaces'] = [[
            'type' => 1,
            'main' => 1,
            'useip' => 1,
            'ip' => '127.0.0.1',
            'dns' => '',
            'port' => '10050',
        ]];
    }
    api('host.update', $update);
}

if (!is_file($adminFile)) {
    $users = api('user.get', ['filter' => ['username' => ['Admin']], 'output' => ['userid']]);
    if (!$users) {
        throw new RuntimeException('Administrator Admin nebyl nalezen');
    }
    $newPassword = bin2hex(random_bytes(24));
    api('user.update', [
        'userid' => $users[0]['userid'],
        'passwd' => $newPassword,
        'current_passwd' => $password,
    ]);
    file_put_contents($adminFile, $newPassword . "\n");
    chmod($adminFile, 0600);
}

echo "Hoste {$localHost} a sposdk.cz jsou pripraveni.\n";
