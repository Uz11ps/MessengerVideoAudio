import paramiko
import socket
import sys
import io

# Устанавливаем UTF-8 для вывода
sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8', errors='replace')

def check_server():
    server = "83.166.246.225"
    port = 22
    user = "root"
    password = "kcokmkzgHQ5dJOBF"
    
    ssh = paramiko.SSHClient()
    ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    
    print(f"Connecting to {server}...")
    ssh.connect(server, port, user, password)
    
    # Проверяем статус PM2
    stdin, stdout, stderr = ssh.exec_command("pm2 status")
    output = stdout.read().decode('utf-8', errors='ignore')
    print("PM2 Status:")
    print(output)
    
    # Проверяем, слушает ли порт 3000
    stdin, stdout, stderr = ssh.exec_command("netstat -tlnp | grep :3000 || ss -tlnp | grep :3000")
    output = stdout.read().decode('utf-8', errors='ignore')
    print("\nPort 3000 status:")
    print(output if output else "Port 3000 not found")
    
    # Проверяем логи
    stdin, stdout, stderr = ssh.exec_command("pm2 logs messenger-backend --lines 20 --nostream")
    output = stdout.read().decode('utf-8', errors='ignore')
    print("\nRecent logs:")
    print(output)
    
    ssh.close()
    
    # Проверяем доступность с клиента
    print("\nChecking server accessibility from client...")
    try:
        sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        sock.settimeout(5)
        result = sock.connect_ex((server, 3000))
        sock.close()
        if result == 0:
            print(f"✓ Server {server}:3000 is accessible")
        else:
            print(f"✗ Server {server}:3000 is NOT accessible (error code: {result})")
    except Exception as e:
        print(f"✗ Error checking server: {e}")

if __name__ == "__main__":
    check_server()
