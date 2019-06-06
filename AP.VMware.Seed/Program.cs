using AP.VMware.Seed.Classes;
using LumenWorks.Framework.IO.Csv;
using Microsoft.EnterpriseManagement;
using Microsoft.EnterpriseManagement.ConnectorFramework;
using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text;
using System.Threading.Tasks;

namespace AP.VMware.Seed
{
    class Program
    {
        // SCOM Functions Instance
        private static SCOM sf = new SCOM();

        // log4net Instance
        private static readonly log4net.ILog log = log4net.LogManager.GetLogger(System.Reflection.MethodBase.GetCurrentMethod().DeclaringType);

        // Config File Name
        private static string m_configFileName = "config.csv";
        // vCenters File Name
        private static string m_vCenterFileName = "vcenters.csv";

        // Management Server Name
        private static string m_managementServer;

        // Create Snapshot Discovery Data Object
        private static SnapshotDiscoveryData discoData = new SnapshotDiscoveryData();

        // List of Clusters
        private static List<VirtualCenterSeed> VirtualCenterList = new List<VirtualCenterSeed>();

        // CSV Position Indicators
        public static int CSV_VCENTER = 0;

        static void Main(string[] args)
        {
            // Write Header
            Console.WriteLine("AP.VMware.Seed, ©A.Patrick 2018-2019");
            Console.WriteLine("Discovers VMware Virtual Centers for SCOM.");
            Console.WriteLine("");

            // First Thing is to get the Managment Server Name from the config file (if it exists).
            m_managementServer = GetManagementServer();
            log.Info("Using management Server " + m_managementServer);

            // See if Config File Exists
            if (File.Exists(m_vCenterFileName))
            {
                // Log Info
                log.Info("Creating Inbound Connector to " + m_managementServer + "...");

                // Get Management Group
                SCOM.m_managementGroup = new ManagementGroup(m_managementServer);

                // Create Our Inbound Connector
                SCOM.CreateConnector();
                log.Info("Inbound Connector Created to " + m_managementServer + "...");

                // Did it Initialise
                if (SCOM.m_monitoringConnector.Initialized)
                {
                    // Log Progress
                    log.Info("Starting Discovery...");
                    Console.WriteLine();
                    // Get Data from vCenters
                    GetData();

                    // Create Discopvery Data
                    Console.WriteLine();
                    log.Info("Creating Discovery Data...");
                    CreateDiscoveryData();

                    try
                    {
                        // Write Discovered Data to SCOM Database 
                        log.Info("Writing Discovery Data to " + m_managementServer);
                        discoData.Overwrite(SCOM.m_monitoringConnector);

                    }
                    catch (Exception ex)
                    {
                        log.Error(ex.Message);
                    }

                    // Uninitialize the connector
                    SCOM.m_monitoringConnector.Uninitialize();
                    SCOM.m_monitoringConnector = null;

                }
                else
                {
                    log.Fatal("Couldn't Initialize Inbound SCOM Connector!");
                }
            } else {
                log.Fatal("Couldn't Find " + m_vCenterFileName);
                Environment.Exit(5);
            }

        }


        /// <summary>
        /// Get Data from vCenters via SDK
        /// </summary>
        private static void GetData()
        {
            // Load In CSV File
            CsvReader csv = new CsvReader(new StreamReader(m_vCenterFileName), true);
            while (csv.ReadNextRecord())
            {
                log.Info(csv[CSV_VCENTER]);


                VirtualCenterSeed newVirtualCenter = new VirtualCenterSeed(csv[CSV_VCENTER]);
                VirtualCenterList.Add(newVirtualCenter);



            }

            // Dispose of CSV
            csv.Dispose();
        }


        /// <summary>
        /// Create Discovery Data
        /// </summary>
        private static void CreateDiscoveryData()
        {
            try
            {
                // Add To Discovery Data
                foreach (VirtualCenterSeed vc in VirtualCenterList)
                {
                    discoData.Include(vc.SCOM_Object);
                }

            }
            catch (Exception ex)
            {
                log.Fatal(ex.Message);
                Environment.Exit(5);
            }
        }


        /// <summary>
        /// Get Management Server
        /// </summary>
        /// <returns>Name of Management Server to Conenct to, localhost if config.csv cannot be found or no entry</returns>
        private static string GetManagementServer()
        {
        // Set to default of localhost
        string mserver = "localhost";

        // See if File Exists
        if (!File.Exists(m_configFileName))
        {
            log.Info("Could not find Config File, config.csv, will use locahost as Management Server Name.");
            return mserver;
        }

        // Load In CSV File
        CsvReader csv = new CsvReader(new StreamReader(m_configFileName), true);
        if (csv.FieldCount == 0)
        {
            log.Info("Config File, config.csv, seems to have no fields please check, will use locahost as Management Server Name.");
        }
        else
        {
            // Read First Record
            csv.ReadNextRecord();
            // Get Management Server Name
            mserver = csv[0].ToString();
        }

        // Dispose of CSV Handler
        csv.Dispose();

        // Return Management Server Name
        return mserver;
    }
    }
}
