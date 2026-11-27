using System;
using System.Collections;
using System.Collections.Generic;
using System.Globalization;
using System.Runtime.InteropServices;
using System.Text;
using System.Web.Script.Serialization;

// Windows system SQLite. Only application-owned statements, bound parameters.
public static class InfinitySqlite {
    const string DLL = "winsqlite3.dll";
    [DllImport(DLL, CallingConvention=CallingConvention.Cdecl)] static extern int sqlite3_open_v2(byte[] name, out IntPtr db, int flags, IntPtr vfs);
    [DllImport(DLL, CallingConvention=CallingConvention.Cdecl)] static extern int sqlite3_close(IntPtr db);
    [DllImport(DLL, CallingConvention=CallingConvention.Cdecl)] static extern int sqlite3_busy_timeout(IntPtr db,int ms);
    [DllImport(DLL, CallingConvention=CallingConvention.Cdecl)] static extern IntPtr sqlite3_errmsg(IntPtr db);
    [DllImport(DLL, CallingConvention=CallingConvention.Cdecl)] static extern int sqlite3_prepare_v2(IntPtr db,byte[] sql,int n,out IntPtr stmt,IntPtr tail);
    [DllImport(DLL, CallingConvention=CallingConvention.Cdecl)] static extern int sqlite3_bind_parameter_count(IntPtr stmt);
    [DllImport(DLL, CallingConvention=CallingConvention.Cdecl)] static extern int sqlite3_bind_null(IntPtr stmt,int i);
    [DllImport(DLL, CallingConvention=CallingConvention.Cdecl)] static extern int sqlite3_bind_text(IntPtr stmt,int i,byte[] value,int size,IntPtr destructor);
    [DllImport(DLL, CallingConvention=CallingConvention.Cdecl)] static extern int sqlite3_step(IntPtr stmt);
    [DllImport(DLL, CallingConvention=CallingConvention.Cdecl)] static extern int sqlite3_finalize(IntPtr stmt);
    [DllImport(DLL, CallingConvention=CallingConvention.Cdecl)] static extern int sqlite3_column_count(IntPtr stmt);
    [DllImport(DLL, CallingConvention=CallingConvention.Cdecl)] static extern IntPtr sqlite3_column_name(IntPtr stmt,int n);
    [DllImport(DLL, CallingConvention=CallingConvention.Cdecl)] static extern IntPtr sqlite3_column_text(IntPtr stmt,int n);
    [DllImport(DLL, CallingConvention=CallingConvention.Cdecl)] static extern int sqlite3_column_bytes(IntPtr stmt,int n);
    static byte[] U8(string s) { return Encoding.UTF8.GetBytes(s+"\0"); }
    static string Z(IntPtr p) { if(p==IntPtr.Zero)return null; int n=0;while(Marshal.ReadByte(p,n)!=0)n++;byte[] b=new byte[n];Marshal.Copy(p,b,0,n);return Encoding.UTF8.GetString(b); }
    static void Check(int rc,IntPtr db) { if(rc!=0)throw new Exception("SQLite "+rc+": "+(db==IntPtr.Zero?"Cannot open database":Z(sqlite3_errmsg(db)))); }
    static List<Dictionary<string,object>> Query(IntPtr db,string sql,IList args) {
        IntPtr st=IntPtr.Zero;
        Check(sqlite3_prepare_v2(db,U8(sql),-1,out st,IntPtr.Zero),db);
        if(st==IntPtr.Zero)throw new Exception("Empty SQL statement");
        try {
            if(sqlite3_bind_parameter_count(st)!=args.Count)throw new Exception("Incorrect SQL parameter count");
            for(int i=0;i<args.Count;i++) {
                if(args[i]==null)Check(sqlite3_bind_null(st,i+1),db);
                else { string s=Convert.ToString(args[i],CultureInfo.InvariantCulture);byte[] b=U8(s);Check(sqlite3_bind_text(st,i+1,b,b.Length-1,new IntPtr(-1)),db); }
            }
            var rows=new List<Dictionary<string,object>>();int rc;
            while((rc=sqlite3_step(st))==100) {
                var row=new Dictionary<string,object>();
                for(int i=0;i<sqlite3_column_count(st);i++) {
                    IntPtr p=sqlite3_column_text(st,i);string value=null;
                    if(p!=IntPtr.Zero){byte[] b=new byte[sqlite3_column_bytes(st,i)];Marshal.Copy(p,b,0,b.Length);value=Encoding.UTF8.GetString(b);}
                    row[Z(sqlite3_column_name(st,i))]=value;
                }
                rows.Add(row);
            }
            if(rc!=101)Check(rc,db);
            return rows;
        } finally { sqlite3_finalize(st); }
    }
    public static string Run(string json) {
        var ser=new JavaScriptSerializer { MaxJsonLength=Int32.MaxValue, RecursionLimit=128 };
        var reply=new Dictionary<string,object>();IntPtr db=IntPtr.Zero;bool transaction=false;
        try {
            var req=ser.Deserialize<Dictionary<string,object>>(json);
            bool ro=Convert.ToBoolean(req["readonly"]);
            Check(sqlite3_open_v2(U8((string)req["database"]),out db,ro?1:6,IntPtr.Zero),db);
            Check(sqlite3_busy_timeout(db,5000),db);
            Query(db,"PRAGMA foreign_keys=ON",new object[0]);
            if(!ro){Query(db,"BEGIN IMMEDIATE",new object[0]);transaction=true;}
            var results=new List<object>();
            foreach(object raw in (IList)req["statements"]) {
                var command=(Dictionary<string,object>)raw;
                results.Add(Query(db,(string)command["sql"],(IList)command["params"]));
            }
            if(transaction){Query(db,"COMMIT",new object[0]);transaction=false;}
            reply["ok"]=true;reply["results"]=results;
        } catch(Exception ex) {
            if(transaction)try{Query(db,"ROLLBACK",new object[0]);}catch{}
            reply["ok"]=false;reply["error"]=ex.Message;
        } finally {if(db!=IntPtr.Zero)sqlite3_close(db);}
        return ser.Serialize(reply);
    }
}
