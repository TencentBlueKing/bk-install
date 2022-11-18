CREATE DATABASE IF NOT EXISTS `bksuite_common`;
use `bksuite_common`;

CREATE TABLE IF NOT EXISTS production_info (
    `index`   INT(11) NOT NULL,
    `code`    VARCHAR(32) NOT NULL PRIMARY KEY COMMENT '模块代码',
    `name`    VARCHAR(32) NOT NULL COMMENT '模块名称',
    `version` VARCHAR(32) NOT NULL COMMENT '版本号',
    UNIQUE KEY `index` (`index`),
    UNIQUE KEY `name` (`name`)
) ENGINE=MyISAM DEFAULT CHARSET=utf8
