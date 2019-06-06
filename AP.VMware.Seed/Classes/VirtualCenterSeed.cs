using Microsoft.EnterpriseManagement.Common;
using Microsoft.EnterpriseManagement.Configuration;
using System.Net;

namespace AP.VMware.Seed.Classes
{
    public class VirtualCenterSeed
    {
        // Virtual Center SCOM Object
        public CreatableEnterpriseManagementObject SCOM_Object;


        // Key Property (Used for Relationship Discovery
        public string m_Key;

        /// <summary>
        /// Default Constructor
        /// </summary>
        /// <param name="FullName">FullName of Virtual Center</param>
        /// <param name="Info">AboutInfo</param>
        public VirtualCenterSeed(string FullName)
        {

            // Get Key Property (MoRef)
            m_Key = FullName;

            // Create Virtual Center Management Pack Class
            ManagementPackClass mpc_VirtualCenterSeed = SCOM.GetManagementPackClass("AP.VMware.VirtualCenter.Seed");
            // Create New Object
            SCOM_Object = new CreatableEnterpriseManagementObject(SCOM.m_managementGroup, mpc_VirtualCenterSeed);

            // Create Root Entity Class & Key Property
            ManagementPackClass mpc_Entity = SCOM.GetManagementPackClass("System.Entity");
            ManagementPackProperty mpp_EntityDisplayName = mpc_Entity.PropertyCollection["DisplayName"];
            SCOM_Object[mpp_EntityDisplayName].Value = FullName;

            // Create Properties of VirtualCenter
            // FullName
            ManagementPackProperty mpp_FullName = mpc_VirtualCenterSeed.PropertyCollection["FullName"];
            SCOM_Object[mpp_FullName].Value = FullName;
            // ShortName
            ManagementPackProperty mpp_ShortName = mpc_VirtualCenterSeed.PropertyCollection["ShortName"];
            SCOM_Object[mpp_ShortName].Value = FullName.Split('.')[0];
            // IPAddress
            IPHostEntry he = Dns.GetHostEntry(FullName);
            ManagementPackProperty mpp_IPAddress = mpc_VirtualCenterSeed.PropertyCollection["IPAddress"];
            SCOM_Object[mpp_IPAddress].Value = he.AddressList[0].ToString();

        }

    }
}
