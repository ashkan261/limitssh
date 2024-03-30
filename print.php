<?php
/**
 * GitHub: RoyalHaze
 * Date: 9/9/23
 * Time: 6:55 PM
 **/

require __DIR__.'/App.php';

$app = new App();

$data = $app->getStoredTraffic();

$i = 1;

foreach ($data as $user => $user_data){
    $upload = $user_data['upload'];
    $download = $user_data['download'];
    $total = $download+$upload;

    echo "$i - $user | U = $upload M | D = $download M | TOTAL = $total M \n";

    $i++;
}
