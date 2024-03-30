<?php

/**
 * GitHub: RoyalHaze
 * Date: 9/9/23
 * Time: 5:54 PM
 **/
class App
{
    public function getTraffic()
    {
        $pid = shell_exec("pgrep nethogs");
        $pid = preg_replace("/\\s+/", "", $pid);
        $newarray = [];

        if (is_numeric($pid)) {
            $out = file_get_contents(__DIR__ . "/out.json");
            $trafficlog = preg_split("/\r\n|\n|\r/", $out);
            $trafficlog = array_filter($trafficlog);
            $lastdata = end($trafficlog);
            $json = json_decode($lastdata, true);
            //print_r($json);

            foreach ($json as $value) {
                $TX = round($value["TX"], 0);
                $RX = round($value["RX"], 0);
                $name = preg_replace("/\\s+/", "", $value["name"]);
                if (strpos($name, "sshd") === false) {
                    $name = "";
                }
                if (strpos($name, "root") !== false) {
                    $name = "";
                }
                if (strpos($name, "/usr/sbin/dropbear") !== false) {
                    $name = "";
                }
                if (strpos($name, "/usr/bin/stunnel4") !== false) {
                    $name = "";
                }
                if (strpos($name, "unknown TCP") !== false) {
                    $name = "";
                }
                if (strpos($name, "/usr/sbin/apache2") !== false) {
                    $name = "";
                }
                if (strpos($name, "[net]") !== false) {
                    $name = "";
                }
                if (strpos($name, "[accepted]") !== false) {
                    $name = "";
                }
                if (strpos($name, "[rexeced]") !== false) {
                    $name = "";
                }
                if (strpos($name, "@notty") !== false) {
                    $name = "";
                }
                if (strpos($name, "root:sshd") !== false) {
                    $name = "";
                }
                if (strpos($name, "/sbin/sshd") !== false) {
                    $name = "";
                }
                if (strpos($name, "[priv]") !== false) {
                    $name = "";
                }
                if (strpos($name, "@pts/1") !== false) {
                    $name = "";
                }
                if ($value["RX"] < 1 && $value["TX"] < 1) {
                    $name = "";
                }
                $name = str_replace("sshd:", "", $name);
                if (!empty($name)) {
                    if (isset($newarray[$name])) {
                        $newarray[$name]["TX"] + $TX;
                        $newarray[$name]["RX"] + $RX;
                    } else {
                        $newarray[$name] = ["RX" => $RX, "TX" => $TX, "Total" => $RX + $TX];
                    }
                }
            }


            shell_exec("sudo kill -9 " . $pid);
            shell_exec("sudo killall -9 nethogs");
        }

        shell_exec("sudo rm -rf ./out.json");
        shell_exec("sudo nethogs -j -d 19 -v 3 > ./out.json &");

        return $newarray;
    }

    public function getUsersList()
    {
        $result = [];
        /** @see http://php.net/manual/en/function.posix-getpwnam.php */
        $keys = ['name', 'passwd', 'uid', 'gid', 'gecos', 'dir', 'shell'];
        $handle = fopen('/etc/passwd', 'r');
        if (!$handle) {
            throw new \RuntimeException("failed to open /etc/passwd for reading! " . print_r(error_get_last(), true));
        }
        while (($values = fgetcsv($handle, 1000, ':')) !== false) {
            $user = array_combine($keys, $values);

            // Check if the user's UID is greater than or equal to 1000 (typical threshold for regular users).
            if ($user['uid'] >= 1000) {
                $result[] = $user;
            }
        }
        fclose($handle);

        return $result;
    }

    public function getParsedUsersList()
    {
        $users = $this->getUsersList();

        return (count($users) == 0)?$users:array_column($users,'name');
    }

    public function syncTraffic()
    {
        $users = $this->getParsedUsersList();

        $old_data = $this->getStoredTraffic();

        $traffic = $this->getTraffic();

        foreach ($traffic as $user => $data){

            if (!in_array($user,$users)){
                continue;
            }

            $rx=round($data["RX"]/1.70);
            $tx=round($data["TX"]/1.70);

            if (isset($old_data[$user])){
                $old_data[$user]['upload'] += $tx;
                $old_data[$user]['download'] += $rx;
            }else{
                $old_data[$user] = [
                  'upload' => $tx,
                  'download' => $rx
                ];
            }
        }

        file_put_contents(__DIR__.'/traffic.json',json_encode($old_data));

        return $old_data;
    }

    public function getStoredTraffic()
    {
        if (!file_exists(__DIR__.'/traffic.json')){
            file_put_contents(__DIR__.'/traffic.json',json_encode([]));
        }

        return json_decode(file_get_contents(__DIR__.'/traffic.json'),true);
    }
}
