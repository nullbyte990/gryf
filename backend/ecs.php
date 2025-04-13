<?php

declare(strict_types=1);

use Symplify\EasyCodingStandard\Config\ECSConfig;

return ECSConfig::configure()
    ->withPaths([
        __DIR__ . '/config',
        __DIR__ . '/src',
    ])
    ->withSkip([
        __DIR__ . '/config/reference.php',
    ])
    ->withPhpCsFixerSets(symfony: true)
    ->withPreparedSets(strict: true, cleanCode: true);
