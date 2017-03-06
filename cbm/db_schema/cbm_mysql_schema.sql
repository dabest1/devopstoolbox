-- MySQL dump 10.13  Distrib 5.6.34, for linux-glibc2.5 (x86_64)
--
-- Host: localhost    Database: cbm
-- ------------------------------------------------------
-- Server version	5.6.34-log

/*!40101 SET @OLD_CHARACTER_SET_CLIENT=@@CHARACTER_SET_CLIENT */;
/*!40101 SET @OLD_CHARACTER_SET_RESULTS=@@CHARACTER_SET_RESULTS */;
/*!40101 SET @OLD_COLLATION_CONNECTION=@@COLLATION_CONNECTION */;
/*!40101 SET NAMES utf8 */;
/*!40103 SET @OLD_TIME_ZONE=@@TIME_ZONE */;
/*!40103 SET TIME_ZONE='+00:00' */;
/*!40014 SET @OLD_UNIQUE_CHECKS=@@UNIQUE_CHECKS, UNIQUE_CHECKS=0 */;
/*!40014 SET @OLD_FOREIGN_KEY_CHECKS=@@FOREIGN_KEY_CHECKS, FOREIGN_KEY_CHECKS=0 */;
/*!40101 SET @OLD_SQL_MODE=@@SQL_MODE, SQL_MODE='NO_AUTO_VALUE_ON_ZERO' */;
/*!40111 SET @OLD_SQL_NOTES=@@SQL_NOTES, SQL_NOTES=0 */;

--
-- Table structure for table `cbm_backup`
--

DROP TABLE IF EXISTS `cbm_backup`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `cbm_backup` (
  `backup_id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `node_name_id` bigint(20) unsigned NOT NULL,
  `start_time` datetime DEFAULT NULL,
  `end_time` datetime DEFAULT NULL,
  `backup_path` varchar(255) DEFAULT NULL,
  `status` varchar(45) DEFAULT NULL,
  `backup_size` bigint(20) DEFAULT NULL COMMENT 'Backup size in bytes.',
  `compressed_size` bigint(20) DEFAULT NULL COMMENT 'Compressed backup size in bytes.',
  `ts_insert` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `ts_update` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`backup_id`),
  UNIQUE KEY `ak1_log` (`node_name_id`,`start_time`)
) ENGINE=InnoDB AUTO_INCREMENT=2967 DEFAULT CHARSET=utf8;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `cbm_cluster`
--

DROP TABLE IF EXISTS `cbm_cluster`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `cbm_cluster` (
  `cluster_id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `cluster_name` varchar(45) DEFAULT NULL,
  `ts_insert` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `ts_update` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`cluster_id`)
) ENGINE=InnoDB AUTO_INCREMENT=28 DEFAULT CHARSET=utf8;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `cbm_node`
--

DROP TABLE IF EXISTS `cbm_node`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `cbm_node` (
  `node_id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `node_name` varchar(45) NOT NULL,
  `cluster_name_id` bigint(20) unsigned NOT NULL,
  `db_type` varchar(45) NOT NULL COMMENT 'Database platform type such as MongoDB, MySQL, Redis, etc.',
  `port` int(11) NOT NULL,
  `ts_insert` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `ts_update` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`node_id`),
  UNIQUE KEY `ak1_mongodb` (`node_name`,`port`)
) ENGINE=InnoDB AUTO_INCREMENT=44 DEFAULT CHARSET=utf8;
/*!40101 SET character_set_client = @saved_cs_client */;
/*!40103 SET TIME_ZONE=@OLD_TIME_ZONE */;

/*!40101 SET SQL_MODE=@OLD_SQL_MODE */;
/*!40014 SET FOREIGN_KEY_CHECKS=@OLD_FOREIGN_KEY_CHECKS */;
/*!40014 SET UNIQUE_CHECKS=@OLD_UNIQUE_CHECKS */;
/*!40101 SET CHARACTER_SET_CLIENT=@OLD_CHARACTER_SET_CLIENT */;
/*!40101 SET CHARACTER_SET_RESULTS=@OLD_CHARACTER_SET_RESULTS */;
/*!40101 SET COLLATION_CONNECTION=@OLD_COLLATION_CONNECTION */;
/*!40111 SET SQL_NOTES=@OLD_SQL_NOTES */;

-- Dump completed
